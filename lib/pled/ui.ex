defmodule Pled.UI do
  @moduledoc """
  UI helper for standardized output and verbosity control.

  Responsibilities:
  - Always-print helpers for errors and the project logo
  - Verbose-gated info and warning messages
  - Centralizes output behavior for consistent UX
  """

  alias Pled.Commands.Help

  @doc """
  Prints the project logo. Always prints.
  """
  def logo do
    Help.logo()
  end

  @doc """
  Prints an informational message only when verbose is true.
  """
  @spec info(iodata(), boolean()) :: :ok
  def info(message, verbose?) when is_boolean(verbose?) do
    if verbose?, do: IO.puts(message)
    :ok
  end

  @doc """
  Prints a warning message only when verbose is true.
  """
  @spec warn(iodata(), boolean()) :: :ok
  def warn(message, verbose?) when is_boolean(verbose?) do
    if verbose?, do: IO.puts(IO.ANSI.yellow() <> message)
    :ok
  end

  @doc """
  Renders an error reason as user-facing text.
  """
  @spec format_reason(term()) :: String.t()
  def format_reason({:remote_unreachable, message}), do: message
  def format_reason({:unauthorized, message}), do: message
  def format_reason(reason) when is_binary(reason), do: reason
  def format_reason(reason), do: inspect(reason)

  @doc """
  Prints an error message. Always prints.
  """
  @spec error(iodata()) :: :ok
  def error(message) do
    IO.puts(IO.ANSI.red() <> message)
    :ok
  end
end
