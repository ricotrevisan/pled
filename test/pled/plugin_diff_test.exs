defmodule Pled.PluginDiffTest do
  use ExUnit.Case, async: false

  alias Pled.PluginDiff

  setup do
    previous = Application.get_env(:pled, :js_ast_runner)

    Application.put_env(:pled, :js_ast_runner, fn source, _opts ->
      {:ok, %{"normalized" => String.replace(source, ~r/\s+/, "")}}
    end)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:pled, :js_ast_runner)
      else
        Application.put_env(:pled, :js_ast_runner, previous)
      end
    end)

    :ok
  end

  describe "diff/2" do
    test "reports metadata field drift" do
      a = base_plugin()
      b = put_in(a, ["description"], "Updated")

      diff = PluginDiff.diff(a, b)

      assert PluginDiff.changed?(diff)
      assert diff.summary[:metadata_field_changed] == 1

      assert Enum.any?(diff.changes, fn change ->
               change.path == ["metadata", "description"] and change.before == "Base" and
                 change.after == "Updated"
             end)
    end

    test "captures element additions" do
      a = base_plugin()
      b = put_in(a, ["plugin_elements", "beta"], sample_element("Beta"))

      diff = PluginDiff.diff(a, b)

      assert diff.summary[:element_added] == 1

      assert Enum.any?(diff.changes, fn change ->
               change.type == :element_added and change.path == ["elements", "beta"]
             end)
    end

    test "emits deep paths for code edits" do
      a = base_plugin()

      b =
        put_in(
          a,
          ["plugin_elements", "alpha", "code", "initialize", "fn"],
          "function(instance) { return 42; }"
        )

      diff = PluginDiff.diff(a, b)

      assert diff.summary == %{element_field_changed: 1}

      assert Enum.any?(diff.changes, fn change ->
               change.type == :element_field_changed and
                 change.path == [
                   "elements",
                   "alpha",
                   "data",
                   "code",
                   "initialize",
                   "fn",
                   "raw"
                 ] and
                 change.before == "function(instance) { return instance; }" and
                 change.after == "function(instance) { return 42; }"
             end)

      refute Enum.any?(diff.changes, &(List.last(&1.path) == "raw_hash"))
    end

    test "ignores code wrapper whitespace when canonical fingerprints match" do
      a = base_plugin()

      b =
        put_in(
          a,
          ["plugin_elements", "alpha", "code", "initialize", "fn"],
          "function ( instance ) {\n  return instance;\n}"
        )

      refute a == b
      refute PluginDiff.changed?(PluginDiff.diff(a, b))
    end
  end

  defp base_plugin do
    %{
      "name" => "Sample",
      "description" => "Base",
      "plugin_elements" => %{"alpha" => sample_element("Alpha")},
      "plugin_actions" => %{"run" => sample_action("Run")}
    }
  end

  defp sample_element(display) do
    %{
      "display" => display,
      "code" => %{
        "initialize" => %{"fn" => "function(instance) { return instance; }"}
      }
    }
  end

  defp sample_action(display) do
    %{
      "display" => display,
      "code" => %{"fn" => "function(properties) { return properties; }"}
    }
  end
end
