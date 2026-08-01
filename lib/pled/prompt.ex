defmodule Pled.Prompt do
  @moduledoc """
  TTY-aware confirmation helper.

  `interactive?/0` reports whether pled can prompt the user. It can be forced
  via the `:pled, :interactive` application env (used in tests); otherwise it
  detects a real terminal.

  `confirm?/2` asks a yes/no question. In non-interactive contexts (or on EOF)
  it returns the default answer instead of raising.
  """

  @spec interactive?() :: boolean()
  def interactive? do
    case Application.get_env(:pled, :interactive, :auto) do
      :auto -> match?({:ok, _}, :io.columns())
      value -> value
    end
  end

  @spec confirm?(String.t(), keyword()) :: boolean()
  def confirm?(prompt, opts \\ []) do
    default = Keyword.get(opts, :default, false)

    if interactive?() do
      case IO.gets(prompt) do
        :eof -> default
        {:error, _} -> default
        answer -> String.downcase(String.trim(answer)) in ["y", "yes"]
      end
    else
      default
    end
  end
end
