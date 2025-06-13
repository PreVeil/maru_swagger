defmodule MaruSwagger.ParamsExtractorTest do
  use ExUnit.Case, async: true
  doctest MaruSwagger.ParamsExtractor
  import TestHelper


  describe "POST" do
    defmodule BasicPostApi do
      use Maru.Router
      desc "res1 create"
      params do
        requires :name, type: :string, source: "user_name"
        requires :email, type: :string
      end
      post "/res1" do
        conn |> json(params)
      end
    end

    test "works with basic POST params" do
      route_info = route_from_module(BasicPostApi, "POST", ["res1"])
      assert {[], %{
        type: "object",
        required: ["user_name", "email"],
        properties: %{
          "user_name" => %{description: "", type: "string"},
          "email" => %{description: "", type: "string"},
        }
      }} == extract_params(route_info)
    end

    test "force json" do
      route_info = route_from_module(BasicPostApi, "POST", ["res1"])
      assert {[], %{
        type: "object",
        required: ["user_name", "email"],
        properties: %{
          "email" => %{description: "", type: "string"},
          "user_name" => %{description: "", type: "string"}}}
      } == extract_params(route_info, %{force_json: true})
    end
  end


  describe "more extensive POST example" do
    defmodule BasicTest.Homepage do
      use Maru.Router
      desc "root page"
      params do
        requires :id, type: Integer
        optional :query, type: List do
          optional :keyword, type: String
        end
      end
      post "/list" do
        _ = params
        conn |> json(%{ hello: :world })
      end

      desc "complex post"
      params do
        requires :name, type: :map do
          requires :first, type: :string
          requires :last, type: :string
        end
        requires :email, type: :string
        optional :age, type: :integer, desc: "age information"
      end
      post "/map" do
        conn |> json(params)
      end

      desc "dependent params"
      params do
        requires :foo, type: Integer
        given [foo: fn val -> val > 10 end] do
          optional :bar
          given :bar do
            requires :qux
          end
        end
        given [foo: fn val -> val < 10 end] do
          requires :baz
        end
      end
      post "/dependent" do
        conn |> json(params)
      end

    end

    defmodule BasicTest.Api do
      use Maru.Router
      mount MaruSwagger.ParamsExtractorTest.BasicTest.Homepage
    end

    test "extracts expected swagger data from nested list params" do
      route_info = route_from_module(BasicTest.Homepage, "POST", ["list"])
      assert {[], %{
        required: ["id"],
        properties: %{
          "id"      => %{description: "", type: "integer" },
          "query"   => %{
            items: %{
              properties: %{
                "keyword" => %{description: "", type: "string"}
              },
              type: "object"
            },
            type: "array" }}}
      } = extract_params(route_info)
    end

    test "extracts expected swagger data from nested map params" do
      route_info = route_from_module(BasicTest.Homepage, "POST", ["map"])
      assert {[], %{
        type: "object",
        required: ["name", "email"],
        properties: %{
          "age"   => %{description: "age information", type: "integer" },
          "email" => %{description: "",                type: "string" },
          "name"  => %{type: "object", properties: %{
            "first" => %{description: "", type: "string" },
            "last" => %{description: "",  type: "string" }
          }}
        }
      }} = extract_params(route_info)
    end

    test "dependent params" do
      route_info = route_from_module(BasicTest.Homepage, "POST", ["dependent"])
      assert {_, %{
        type: "object",
        required: ["foo"],
        properties: %{
          "foo" => %{type: "integer"},
          "bar" => %{type: "string"},
          "qux" => %{type: "string"},
          "baz" => %{type: "string"}
        }
      }} = extract_params(route_info)
    end
  end

  describe "one-line nested list test" do
    defmodule OneLineNestedList do
      use Maru.Router

      desc "one-line nested list test"
      params do
        requires :foo, type: List[String]
      end
      post "/path" do
        conn |> json(params)
      end
    end

    test "one-line nested list test" do
      route_info = route_from_module(OneLineNestedList, "POST", ["path"])
      assert {_, %{
        type: "object",
        required: ["foo"],
        properties: %{
          "foo" => %{
            type: "array", items: %{type: "string"}
          }
        }
      }} = extract_params(route_info)
    end
  end

end
