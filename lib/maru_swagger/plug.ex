defmodule MaruSwagger.Plug do
  use Maru.Middleware
  alias MaruSwagger.ConfigStruct
  alias Plug.Conn

  alias Maru.Struct.Parameter.Information

  def init(opts) do
    ConfigStruct.from_opts(opts)
  end

  def call(%Conn{path_info: path}=conn, %ConfigStruct{path: path}=config) do
    resp = generate(config) |> Poison.encode!(pretty: config.pretty)
    conn
    |> Conn.put_resp_header("access-control-allow-origin", "*")
    |> Conn.put_resp_content_type("application/json")
    |> Conn.send_resp(200, resp)
    |> Conn.halt
  end
  def call(conn, _) do
    # TODO: figure out why we'd want to modify conn for other paths.
    #conn |> Conn.put_resp_header("access-control-allow-origin", "*")
    conn
  end

  # -------- ----- --- -- - -  -   -     -        -
  # (move this to another file?)

  # A route.parameter.runtime is of AST type.
  # Within it, there are validate_func bodies, and within those,
  #  we can grab allowed values for atom types.
  # Unhandled edge case: nested params with same name in multiple places.
  defp get_atom_param_allowed_vals(ast) do
    # Within the runtime AST, there are a couple tuples relatively unique
    #  to the body of a :validate_func that we can match on:
    maru_validate_tuple = {:., [], [Maru.Validations.Values, :validate_param!]}
    maru_param_metadata = {:value, [], Maru.Builder.Params}

    # As we walk over the AST:
    # - always return the original form unchanged
    # - if we match on a param & allowed values pair, grab and merge into acc
    walk_capturing_param_kw_and_vals = fn
      ({^maru_validate_tuple, [],
        [param_kw,
         ^maru_param_metadata,
         [_ | _]=param_vs] # ensure list, not tuple (want atom values, not integer)
       }=form, acc) -> {form, Map.merge(acc, %{param_kw => param_vs})}
      (form, acc) -> {form, acc}
    end

    {_, acc} = Macro.postwalk(ast, %{}, walk_capturing_param_kw_and_vals)
    acc
  end

  # Nonnested parameter:
  defp cast_atom_to_enum(
    {atom_k, vs},
    %Information{type: "atom",
             children: [],
            attr_name: attr
    }=info
  ) do # that matches the key:
    if attr == atom_k do
      Map.merge(info, %{type: "string", enum: vs})
    else # that doesn't match:
      info
    end
  end
  # Nested parameter; recurse through child parameters:
  defp cast_atom_to_enum(
    k_to_vs,
    %Information{type: "map",
             children: children
    }=info
  ) do
    Map.merge(info, %{children: Enum.map(children, &cast_atom_to_enum(k_to_vs, &1))})
  end
  # noop for remainder (parameter neither nested nor of atom type):
  defp cast_atom_to_enum(_, info), do: info

  defp cast_atom_parameters_to_enums({param_info, atom_ks_to_allowed_values}) do
    Enum.reduce(atom_ks_to_allowed_values, param_info, &cast_atom_to_enum/2)
  end

  defp modify_parameters_for_atoms(route) do
    route.parameters
    |> Enum.map(&{&1.information, get_atom_param_allowed_vals(&1.runtime)})
    |> Enum.map(&cast_atom_parameters_to_enums/1)
  end

  #
  # -------- ----- --- -- - -  -   -     -        -

  def generate(%ConfigStruct{}=config) do
    c = (Application.get_env(:maru, config.module) || [])[:versioning] || []
    adapter = Maru.Builder.Versioning.get_adapter(c[:using])
    routes =
      config.module.__routes__
      |> Enum.map(fn route ->
        #parameters = Enum.map(route.parameters, &(&1.information))
        parameters = modify_parameters_for_atoms(route)
        %{ route | parameters: parameters }
      end)
    tags =
      routes
      |> Enum.map(&(&1.version))
      |> Enum.uniq
      |> Enum.map(fn v -> %{name: tag_name(v)} end)
    routes =
      routes
      |> Enum.map(&extract_route(&1, adapter, config))
    MaruSwagger.ResponseFormatter.format(routes, tags, config)
  end

  defp extract_route(ep, adapter, config) do
    params = MaruSwagger.ParamsExtractor.extract_params(ep, config)
    path   = adapter.path_for_params(ep.path, ep.version)
    method = case ep.method do
      {:_, [], nil} -> "MATCH"
      m             -> m
    end
    %{
      desc:    ep.desc,
      method:  method,
      path:    path,
      params:  params,
      tag:     tag_name(ep.version),
    }
  end

  defp tag_name(nil), do: "DEFAULT"
  defp tag_name(v),   do: "Version: #{v}"

end
