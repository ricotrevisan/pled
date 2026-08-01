defmodule Pled.CodeBlock do
  @moduledoc """
  Represents a JavaScript snippet along with its parsed AST metadata.

  Instances store the original source code, parser diagnostics, and a
  whitespace-insensitive fingerprint (AST hash when available, otherwise the raw
  text hash). The struct can be reduced to a serializable map so
  `Pled.PluginModel` can embed code blocks inside canonical data.
  """

  alias Pled.{JsAst, PluginModel}

  @enforce_keys [:raw]
  defstruct raw: "",
            raw_hash: nil,
            ast: nil,
            ast_hash: nil,
            fingerprint: nil,
            parser: :text,
            diagnostics: [],
            path: []

  @type t :: %__MODULE__{
          raw: String.t(),
          raw_hash: String.t(),
          ast: map() | nil,
          ast_hash: String.t() | nil,
          fingerprint: String.t(),
          parser: :text | :ast,
          diagnostics: [map()],
          path: [String.t()]
        }

  @doc """
  Builds a `CodeBlock` from raw source.

  Options:
    * `:path` - path list used in diagnostics
    * `:module?` - treat snippet as an ES module (`false` by default)
  """
  @spec from_source(String.t(), keyword()) :: t()
  def from_source(source, opts \\ []) when is_binary(source) do
    path = Keyword.get(opts, :path, [])
    raw_hash = PluginModel.hash_term(source)

    case JsAst.parse(source, opts) do
      {:ok, ast} ->
        ast_hash = PluginModel.hash_term(ast)

        %__MODULE__{
          raw: source,
          raw_hash: raw_hash,
          ast: ast,
          ast_hash: ast_hash,
          fingerprint: ast_hash,
          parser: :ast,
          diagnostics: [],
          path: path
        }

      {:error, error} ->
        %__MODULE__{
          raw: source,
          raw_hash: raw_hash,
          ast: nil,
          ast_hash: nil,
          fingerprint: raw_hash,
          parser: :text,
          diagnostics: [format_error(error, path)],
          path: path
        }
    end
  end

  @doc """
  Converts the code block into a JSON-friendly map.
  """
  @spec to_serializable(t()) :: map()
  def to_serializable(%__MODULE__{} = block) do
    %{
      "__type" => "code_block",
      "raw" => block.raw,
      "raw_hash" => block.raw_hash,
      "ast_hash" => block.ast_hash,
      "fingerprint" => block.fingerprint,
      "parser" => Atom.to_string(block.parser),
      "diagnostics" => block.diagnostics
    }
  end

  @doc """
  Extracts the function signature (e.g. `"async function(properties, context)"`)
  from a function source string. The decoder stores this signature in the
  cleaned action json and the encoder re-parses it to rebuild the exact
  remote wrapper.
  """
  @spec signature(String.t()) :: {:ok, String.t()} | :error
  def signature(fn_source) when is_binary(fn_source) do
    case Regex.run(~r/^\s*(?:async\s+)?function\s*\([^)]*\)/, fn_source) do
      [signature | _] -> {:ok, String.trim(signature)}
      nil -> :error
    end
  end

  def signature(_), do: :error

  @doc """
  True when the block has a parsed AST.
  """
  @spec ast?(t()) :: boolean()
  def ast?(%__MODULE__{ast: nil}), do: false
  def ast?(%__MODULE__{}), do: true

  @doc """
  Returns the canonical fingerprint used for comparisons.
  """
  @spec fingerprint(t()) :: String.t()
  def fingerprint(%__MODULE__{fingerprint: fingerprint}), do: fingerprint

  defp format_error(%{reason: reason, message: message, details: details}, path) do
    %{
      reason: reason,
      message: message,
      details: details,
      path: path
    }
  end

  defp format_error(_, path) do
    %{
      reason: :unknown,
      message: "Unknown parser error",
      details: %{},
      path: path
    }
  end
end
