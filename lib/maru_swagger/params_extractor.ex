defmodule MaruSwagger.ParamsExtractor do
  alias Maru.Struct.Parameter.Information, as: PI
  alias Maru.Struct.Dependent.Information, as: DI

  def schema_fields(), do: [:maxLength, :pattern, :format, :maximum, :minimum, :items, :maxItems]

  defmodule NonGetBodyParamsGenerator do
    def generate(param_list, path, config) do
      {path_param_list, body_param_list} =
        param_list
        |> MaruSwagger.ParamsExtractor.filter_information
        |> Enum.split_with(&(&1.attr_name in path))
      {
        format_path_params(path_param_list, config),
        format_body_params(body_param_list, config)
      }
    end

    defp format_path_params(param_list, config) do
      Enum.map(param_list, fn param ->
        %{ name:        param.param_key,
           description: param.desc || "",
           required:    param.required,
           in:          "path",
        } |> MaruSwagger.ParamsExtractor.populate_param_schema(param)
      end)
      |> Enum.map(&MaruSwagger.ParamsExtractor.include_example(&1, config))
    end

    defp format_body_params(params, config) do
      formatted = %{
        type: "object",
        properties:
          for param <- params do
            {param.param_key, format_body_param(param.type, param, config)}
          end
          |> Map.new()
      }

      required = for p <- params, p.required, do: p.param_key
      if required != [] do
        Map.put(formatted, :required, required)
      else
        formatted
      end
    end

    defp format_body_param("map", param, config) do
      %{
        type: "object",
        properties:
          for child <- param.children do
            {child.param_key, format_body_param(child.type, child, config)}
          end
          |> Map.new()
      }
    end

    defp format_body_param("list", param, config) do
      Map.merge %{
        type: "array",
        maxItems: 9007199254740991,
        items: %{
          type: "object",
          properties:
            for child <- param.children do
              {child.param_key, format_body_param(child.type, child, config)}
            end
            |> Map.new()
        }
      }, Map.take(param, [:maxItems])
    end

    defp format_body_param({:list, type}, param, config) do
      Map.merge %{
        type: "array",
        maxItems: 9007199254740991,
        items: format_body_param(type, param, config)
      }, Map.take(param, [:maxItems])
    end

    defp format_body_param(type, param, config) do
      formatted = %{
        type: type,
        description: Map.get(param, :desc) || ""
      }
      formatted = if Map.has_key?(config.examples, param.param_key) do
        Map.put(formatted, :example, Map.get(config.examples, param.param_key))
      else
        formatted
      end
      Map.merge(formatted, Map.take(param, MaruSwagger.ParamsExtractor.schema_fields()))
    end
  end

  def populate_param_schema(formatted, input) do
    Map.put(formatted, :schema, Map.take(input, [:type | schema_fields()]))
  end

  alias Maru.Struct.Route
  def extract_params(%Route{method: {:_, [], nil}}=ep, config) do
    extract_params(%{ep | method: "MATCH"}, config)
  end

  def extract_params(%Route{method: "GET", path: path, parameters: parameters}, config) do
    url_params = for %PI{} = param <- parameters do
      %{ name:        param.param_key,
         description: param.desc || "",
         required:    param.required,
         in:          param.attr_name in path && "path" || "query",
      } |> populate_param_schema(param)
    end
    |> Enum.map(&include_example(&1, config))
    {url_params, %{}}
  end
  def extract_params(%Route{method: "GET"}, _config), do: {[], %{}}
  def extract_params(%Route{parameters: []}, _config), do: {[], %{}}

  def extract_params(%Route{parameters: param_list, path: path}, config) do
    param_list = filter_information(param_list)
    NonGetBodyParamsGenerator.generate(param_list, path, config)
  end

  def include_example(param = %{name: name}, %{examples: examples}) do
    if Map.has_key?(examples, name) do
      Map.put(param, :example, Map.get(examples, name))
    else
      param
    end
  end

  def filter_information(param_list) do
    Enum.filter(param_list, fn
      %PI{} -> true
      %DI{} -> true
      _     -> false
    end) |> flatten_dependents
  end

  def flatten_dependents(param_list, force_optional \\ false) do
    Enum.reduce(param_list, [], fn
      %PI{}=i, acc when force_optional ->
        do_append(acc, %{i | required: false})
      %PI{}=i, acc ->
        do_append(acc, i)
      %DI{children: children}, acc ->
        flatten_dependents(children, true)
        |> Enum.reduce(acc, fn(i, deps) ->
          do_append(deps, i)
        end)
    end)
  end

  defp do_append(param_list, i) do
    Enum.any?(param_list, fn(param) ->
      param.param_key == i.param_key
    end)
    |> case do
      true  -> param_list
      false -> param_list ++ [i]
    end
  end

end
