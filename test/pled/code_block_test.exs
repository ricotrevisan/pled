defmodule Pled.CodeBlockTest do
  use ExUnit.Case, async: false

  alias Pled.CodeBlock

  setup do
    original = Application.get_env(:pled, :js_ast_runner)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:pled, :js_ast_runner)
      else
        Application.put_env(:pled, :js_ast_runner, original)
      end
    end)

    :ok
  end

  test "stores AST fingerprint when parser succeeds" do
    ast = %{"type" => "Program", "body" => []}

    Application.put_env(:pled, :js_ast_runner, fn _source, _opts ->
      {:ok, ast}
    end)

    block = CodeBlock.from_source("function demo() {}", path: ["elements", "alpha"])

    assert block.parser == :ast
    assert block.ast == ast
    assert block.fingerprint == block.ast_hash
    assert block.diagnostics == []
  end

  test "falls back to text when parser fails" do
    Application.put_env(:pled, :js_ast_runner, fn _, _ ->
      {:error, %{reason: :parse_error, message: "boom", details: %{line: 1}}}
    end)

    block = CodeBlock.from_source("function invalid(", path: ["elements", "beta", "fn"])

    assert block.parser == :text
    refute CodeBlock.ast?(block)
    assert block.fingerprint == block.raw_hash
    assert [%{reason: :parse_error, path: ["elements", "beta", "fn"]}] = block.diagnostics
  end
end
