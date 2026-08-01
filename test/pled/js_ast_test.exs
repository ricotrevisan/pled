defmodule Pled.JsAstTest do
  use ExUnit.Case, async: false

  alias Pled.JsAst

  setup do
    previous = Application.get_env(:pled, :js_ast_runner)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:pled, :js_ast_runner)
      else
        Application.put_env(:pled, :js_ast_runner, previous)
      end
    end)

    :ok
  end

  test "with_cache reuses duplicate parse results only within its scope" do
    test_process = self()

    Application.put_env(:pled, :js_ast_runner, fn source, opts ->
      send(test_process, {:parsed, source, opts[:module?]})
      {:ok, %{"source" => source}}
    end)

    JsAst.with_cache(fn ->
      assert {:ok, %{"source" => "const value = 1"}} = JsAst.parse("const value = 1")
      assert {:ok, %{"source" => "const value = 1"}} = JsAst.parse("const value = 1")
    end)

    assert_received {:parsed, "const value = 1", nil}
    refute_received {:parsed, "const value = 1", nil}

    assert {:ok, _ast} = JsAst.parse("const value = 1")
    assert_received {:parsed, "const value = 1", nil}
  end
end
