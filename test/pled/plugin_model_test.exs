defmodule Pled.PluginModelTest do
  use ExUnit.Case, async: false

  alias Pled.PluginModel

  setup context do
    original = Application.get_env(:pled, :js_ast_runner)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:pled, :js_ast_runner)
      else
        Application.put_env(:pled, :js_ast_runner, original)
      end
    end)

    if runner_tag = context[:js_runner] do
      Application.put_env(:pled, :js_ast_runner, runner_for(runner_tag))
    end

    :ok
  end

  describe "from_remote/1" do
    test "sorts elements deterministically by key" do
      plugin = %{
        "name" => "Sortable",
        "plugin_elements" => %{
          "b" => sample_element("Second"),
          "a" => sample_element("First")
        }
      }

      {:ok, model} = PluginModel.from_remote(plugin)
      assert Enum.map(model.elements, & &1.key) == ["a", "b"]
    end
  end

  describe "fingerprint/1" do
    @tag js_runner: :hash_based
    test "ignores map ordering differences" do
      plugin_a = base_plugin()

      plugin_b = %{
        "plugin_elements" => plugin_a["plugin_elements"] |> Enum.reverse() |> Map.new(),
        "name" => plugin_a["name"],
        "description" => plugin_a["description"]
      }

      assert PluginModel.equal?(plugin_a, plugin_b)
    end

    @tag js_runner: :hash_based
    test "detects substantive code differences" do
      plugin_a = base_plugin()

      plugin_b =
        put_in(
          plugin_a,
          ["plugin_elements", "alpha", "code", "initialize", "fn"],
          "function() { return 42; }"
        )

      refute PluginModel.equal?(plugin_a, plugin_b)
    end

    @tag js_runner: :constant_program
    test "ignores whitespace differences when AST parsing succeeds" do
      plugin_a = base_plugin()

      plugin_b =
        put_in(
          plugin_a,
          ["plugin_elements", "alpha", "code", "initialize", "fn"],
          "function(instance){return instance;}"
        )

      assert PluginModel.equal?(plugin_a, plugin_b)
    end
  end

  describe "code block wrapping" do
    test "replaces fn strings with serializable metadata" do
      {:ok, model} = PluginModel.from_remote(base_plugin())

      element = Enum.find(model.elements, &(&1.key == "alpha"))

      fn_map = get_in(element.data, ["code", "initialize", "fn"])

      assert fn_map["__type"] == "code_block"
      assert fn_map["raw"] =~ "function(instance)"
      assert is_binary(fn_map["fingerprint"])
    end
  end

  defp base_plugin do
    %{
      "name" => "Sample",
      "description" => "demo",
      "plugin_elements" => %{
        "beta" => sample_element("Second"),
        "alpha" => sample_element("First")
      }
    }
  end

  defp sample_element(display) do
    %{
      "display" => display,
      "code" => %{
        "initialize" => %{"fn" => "function(instance) { return instance; }"}
      },
      "actions" => %{
        "run" => %{"caption" => "Run", "code" => %{"fn" => "function() {}"}}
      }
    }
  end

  defp runner_for(:constant_program) do
    fn _, _ -> {:ok, %{"type" => "Program", "value" => 42}} end
  end

  defp runner_for(:hash_based) do
    fn source, _opts ->
      hash = :crypto.hash(:sha256, source) |> Base.encode16(case: :lower)
      {:ok, %{"type" => "Program", "hash" => hash}}
    end
  end

  defp runner_for(other), do: other
end
