defmodule Pled.PluginIdTest do
  use ExUnit.Case, async: false

  alias Pled.PluginId

  @plugin_id_file ".plugin_id"

  setup do
    original_plugin_id = System.get_env("PLUGIN_ID")
    File.rm(@plugin_id_file)

    on_exit(fn ->
      File.rm(@plugin_id_file)

      if original_plugin_id do
        System.put_env("PLUGIN_ID", original_plugin_id)
      else
        System.delete_env("PLUGIN_ID")
      end
    end)

    :ok
  end

  describe "extract/1" do
    test "extracts ID from full Bubble plugin editor URL" do
      assert {:ok, "1670612027178x122079323974008830"} =
               PluginId.extract(
                 "https://bubble.io/plugin_editor?id=1670612027178x122079323974008830"
               )
    end

    test "extracts ID from URL with extra params" do
      assert {:ok, "1234x5678"} =
               PluginId.extract("https://bubble.io/plugin_editor?id=1234x5678&tab=tabs-4")
    end

    test "extracts raw ID" do
      assert {:ok, "1234x5678"} = PluginId.extract("1234x5678")
    end

    test "handles whitespace" do
      assert {:ok, "1234x5678"} = PluginId.extract("  1234x5678  ")
    end

    test "returns error for invalid input" do
      assert :error = PluginId.extract("not-a-valid-id")
    end

    test "returns error for URL without id param" do
      assert :error = PluginId.extract("https://bubble.io/plugin_editor")
    end
  end

  describe "load/0" do
    test "reads from .plugin_id file" do
      System.delete_env("PLUGIN_ID")
      File.write!(@plugin_id_file, "111x222\n")

      assert {:ok, "111x222"} = PluginId.load()
    end

    test "falls back to env var when no file" do
      System.put_env("PLUGIN_ID", "333x444")

      assert {:ok, "333x444"} = PluginId.load()
    end

    test "prefers file over env var" do
      File.write!(@plugin_id_file, "111x222\n")
      System.put_env("PLUGIN_ID", "333x444")

      assert {:ok, "111x222"} = PluginId.load()
    end

    test "returns error when neither file nor env var exists" do
      System.delete_env("PLUGIN_ID")

      assert {:error, _msg} = PluginId.load()
    end

    test "returns error for empty file" do
      System.delete_env("PLUGIN_ID")
      File.write!(@plugin_id_file, "  \n")

      assert {:error, _msg} = PluginId.load()
    end
  end

  describe "save/1" do
    test "writes ID to file" do
      PluginId.save("555x666")

      assert File.read!(@plugin_id_file) == "555x666\n"
    end
  end

  describe "source/0" do
    test "returns :file when .plugin_id exists" do
      File.write!(@plugin_id_file, "111x222\n")

      assert {:ok, :file} = PluginId.source()
    end

    test "returns :env when only env var is set" do
      System.put_env("PLUGIN_ID", "333x444")

      assert {:ok, :env} = PluginId.source()
    end

    test "returns :error when neither exists" do
      System.delete_env("PLUGIN_ID")

      assert :error = PluginId.source()
    end
  end
end
