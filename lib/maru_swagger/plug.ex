defmodule MaruSwagger.Plug do
  use Maru.Middleware
  alias MaruSwagger.ConfigStruct
  alias Plug.Conn

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
  defp runtime_to_atom_values(ast) do
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

  # Navigate parameter information (and potential children):
  defp postwalk_params(%{type: "map", children: children}=info, f) do
    info = f.(info)
    children = Enum.map(children, &postwalk_params(&1, f))
    Map.merge(info, %{children: children})
    # With this merge order, children may not be modified at the parent level.
    # (Any modifications that are done to them will be overwritten.)
  end
  defp postwalk_params(info, f), do: f.(info)
  # Separating the navigation from the operation allows us to compose
  #  multiple operators, applying all of them but only navigating once.

  # Here's one operation:
  # (it requires additional info to work)
  defp make_cast_atoms_to_enums(atom_keys_to_allowed_values) do
    fn %{type: "atom", children: [], attr_name: attr}=info -> (
      vs = atom_keys_to_allowed_values[attr]
      if vs do # this atom param matches, cast it to enum:
        Map.merge(info, %{type: "string", enum: vs})
      else # or it doesn't, leave it unchanged:
        info
      end)
      info -> info
    end
  end

  defp cast_mapt_to_json(%{type: "mapt", children: []}=info) do
    Map.merge(info, %{type: "object", additional_properties: true})
  end
  defp cast_mapt_to_json(info), do: info

  defp cast_uuid_to_string_format(%{type: "uuid", children: []}=info) do
    Map.merge(info, %{type: "string", format: "uuid"})
  end
  defp cast_uuid_to_string_format(info), do: info

  # Only works for single-arg functions
  defp comp(f, g) do
    fn arg -> g.(f.(arg)) end
  end
  defp r_comp([_ | _]=functions) do
    Enum.reduce(functions, &comp/2)
  end

  defp modify_parameters_types(route) do
    route.parameters
    |> Enum.map(fn parameter ->
      rt = parameter.runtime
      atom_values = runtime_to_atom_values(rt)
      cast_atoms_to_enums = make_cast_atoms_to_enums(atom_values)
      type_transforms = [
        &cast_mapt_to_json/1,
        &cast_uuid_to_string_format/1,
        # TODO: take above fns from config, rather than hardcoding.
        # (That way users can define custom transforms, based on name or type.)
        cast_atoms_to_enums
      ]
      xf = r_comp(type_transforms)
      parameter.information
      |> postwalk_params(xf)
    end)
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
        #parameters = modify_parameters_for_atoms(route)
        parameters = modify_parameters_types(route)
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
