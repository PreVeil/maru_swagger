defmodule MaruSwagger.ConfigStruct do
  defstruct [
    :path,           # [string]  where to mount the Swagger JSON
    :module,         # [atom]    Maru API module
    :force_json,     # [boolean] force JSON for all params instead of formData
    :pretty,         # [boolean] should JSON output be prettified?
    :swagger_inject, # [keyword list] key-values to inject directly into root of Swagger JSON
    :info,           # [map] added beneath "info" key of produced JSON
    # For custom parameter types, additional conversions may be needed for OAS compliance:
    :type_transform, # %{} :: %{}, %{} ≈ Maru.Struct.Parameter.Information
    :param_opt_keys, # [keywords] additional keywords that type_transform may add to params
  ]


  def from_opts(opts) do
    path           = opts |> Keyword.fetch!(:at) |> Maru.Builder.Path.split
    module         = opts |> Keyword.fetch!(:module)
    force_json     = opts |> Keyword.get(:force_json, false)
    pretty         = opts |> Keyword.get(:pretty, false)
    swagger_inject = opts |> Keyword.get(:swagger_inject, []) |> Keyword.put_new_lazy(:basePath, base_path_func(module)) |> check_swagger_inject_keys
    info = opts |> Keyword.get(:info) # No formatting or exclusion; use map directly.
    type_transform = opts |> Keyword.get(:type_transform)
    param_opt_keys = opts |> Keyword.get(:param_opt_keys)

    %__MODULE__{
      path: path,
      module: module,
      force_json: force_json,
      pretty: pretty,
      swagger_inject: swagger_inject,
      info: info,
      type_transform: type_transform,
      param_opt_keys: param_opt_keys,
    }
  end

  defp base_path_func(module) do
    fn ->
      [ "" |
        if Code.ensure_loaded?(Phoenix) do
          phoenix_module = Module.concat(Mix.Phoenix.base(), "Router")
          phoenix_module.__routes__ |> Enum.filter(fn r ->
            match?(%{kind: :forward, plug: ^module}, r)
          end)
          |> case do
            [%{path: p}] -> p |> String.split("/", trim: true)
            _            -> []
          end
        else
          []
        end
      ] |> Enum.join("/")
    end
  end

  defp check_swagger_inject_keys(swagger_inject) do
    swagger_inject |> Enum.filter(fn {k, v} ->
      k in allowed_swagger_fields() and not v in [nil, ""]
    end)
  end

  defp allowed_swagger_fields do
    [:host, :basePath, :schemes, :consumes, :produces]
  end

end
