defmodule MaruSwagger.ParamsExtractor do
  alias Maru.Struct.Parameter.Information, as: PI
  alias Maru.Struct.Dependent.Information, as: DI

  defmodule NonGetBodyParamsGenerator do
    def generate(param_list, path, config) do
      {path_param_list, body_param_list} =
        param_list
        |> MaruSwagger.ParamsExtractor.filter_information
        |> Enum.partition(&(&1.attr_name in path))
      [ format_body_params(body_param_list, config) |
        format_path_params(path_param_list, config)
      ]
    end

    defp default_body do
      %{ name: "body",
         in: "body",
         description: "",
         required: false,
       }
    end

    defp format_path_params(param_list, config) do
      Enum.map(param_list, fn param ->
        %{ name:        param.param_key,
           description: param.desc || "",
           type:        param.type,
           required:    param.required,
           in:          "path",
        } |> MaruSwagger.ParamsExtractor.inject_opt_keys(param, config)
      end)
    end

    defp format_body_params(param_list, config) do
      param_list
      |> Enum.map(&format_param(&1, config))
      |> case do
        []     -> default_body()
        params ->
          params = Enum.into(params, %{})
          default_body()
          |> put_in([:schema], %{})
          |> put_in([:schema, :properties], params)
      end
    end


    defp format_param(param, config) do
      {param.param_key, do_format_param(param.type, param, config)}
    end

    defp do_format_param("map", param, config) do
      %{ type: "object",
         properties: param.children |> Enum.map(&format_param(&1, config)) |> Enum.into(%{}),
      }
    end

    defp do_format_param("list", param, config) do
      %{ type: "array",
         items: %{
           type: "object",
           properties: param.children |> Enum.map(&format_param(&1, config)) |> Enum.into(%{}),
         }
      }
    end

    defp do_format_param({:list, type}, param, config) do
      %{ type: "array",
         items: do_format_param(type, param, config),
      }
    end

    defp do_format_param(type, param, config) do
      %{ description: param.desc || "",
         type:        type,
         required:    param.required,
      }
      |> MaruSwagger.ParamsExtractor.inject_opt_keys(param, config)
    end

  end

  defmodule NonGetFormDataParamsGenerator do
    def generate(param_list, path, config) do
      param_list
      |> MaruSwagger.ParamsExtractor.filter_information
      |> Enum.map(fn param ->
        %{ name:        param.param_key,
           description: param.desc || "",
           type:        param.type,
           required:    param.required,
           in:          param.attr_name in path && "path" || "formData",
        } |> MaruSwagger.ParamsExtractor.inject_opt_keys(param, config)
      end)
    end
  end

  def inject_opt_keys(map, param, config) do
    opts = [:enum | (Map.get(config, :param_opt_keys) || [])]
    opts_map = Map.take(param, opts)
    Map.merge(map, opts_map)
  end

  alias Maru.Struct.Route
  def extract_params(%Route{method: {:_, [], nil}}=ep, config) do
    extract_params(%{ep | method: "MATCH"}, config)
  end

  def extract_params(%Route{method: "GET", path: path, parameters: parameters}, config) do
    for param <- parameters do
      %{ name:        param.param_key,
         description: param.desc || "",
         required:    param.required,
         type:        param.type,
         in:          param.attr_name in path && "path" || "query",
      } |> inject_opt_keys(param, config)
    end
  end
  def extract_params(%Route{method: "GET"}, _config), do: []
  def extract_params(%Route{parameters: []}, _config), do: []

  def extract_params(%Route{parameters: param_list, path: path}, config) do
    param_list = filter_information(param_list)
    generator =
      if config.force_json do
        NonGetBodyParamsGenerator
      else
        case judge_adapter(param_list) do
          :body      -> NonGetBodyParamsGenerator
          :form_data -> NonGetFormDataParamsGenerator
        end
      end
    generator.generate(param_list, path, config)
  end

  defp judge_adapter([]),                        do: :form_data
  defp judge_adapter([%{type: "list"} | _]),     do: :body
  defp judge_adapter([%{type: "map"} | _]),      do: :body
  defp judge_adapter([%{type: {:list, _}} | _]), do: :body
  defp judge_adapter([_ | t]),                   do: judge_adapter(t)

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
