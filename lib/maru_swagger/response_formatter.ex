defmodule MaruSwagger.ResponseFormatter do
  alias MaruSwagger.ConfigStruct

  def format(routes, tags, config=%ConfigStruct{}) do
    paths = routes |> List.foldr(%{}, fn (%{desc: desc, method: method, path: url_list, url_params: url_params, body_params: body_params, tag: tag}, result) ->
      desc = desc || %{}
      responses = desc[:responses] || [%{code: 200, description: "ok"}]
      url = join_path(url_list)
      result = if Map.has_key? result, url do
        result
      else
        result |> put_in([url], %{})
      end

      route = %{
        tags: [tag],
        description: desc[:detail] || "",
        summary: desc[:summary] || "",
        parameters: url_params,

        responses: for r <- responses, into: %{} do
          {to_string(r.code), %{description: r.description}}
        end
      }
      |> Map.merge(request_body(body_params))
      
      put_in(result, [url, String.downcase(method)], route)
    end)
    wrap_in_swagger_info(paths, tags, config)
  end

  defp request_body(body_params) when body_params == %{} do
    %{}
  end
  
  defp request_body(body_params) do
    %{
      requestBody: %{
        content: %{
          "application/json" => %{
            schema: body_params
          }
        }
      }
    }
  end

  defp wrap_in_swagger_info(paths, tags, config=%ConfigStruct{}) do
    res = %{
      openapi: "3.0.0",
      info:
        case config.info do
          %{} -> config.info # No need to format; use unchanged.
          _   -> format_default(config)
        end,
      paths: paths,
      tags: tags,
    }

    for {k,v} <- (config.swagger_inject || []), into: res, do: {k,v}
  end

  defp format_default(config) do
    %{title: "Swagger API for #{elixir_module_name(config.module)}"}
  end

  defp elixir_module_name(module) do
    "Elixir." <> m = module |> to_string
    m
  end

  defp join_path(path) do
    [ "/" | for i <- path do
      cond do
        is_atom(i) -> "{#{i}}"
        is_binary(i) -> i
        true -> raise "unknow path type"
      end
    end ] |> Path.join
  end

end
