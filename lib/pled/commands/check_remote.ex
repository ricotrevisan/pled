defmodule Pled.Commands.CheckRemote do
  @moduledoc """
  Command to report the three-way sync state without changing it.
  """

  alias Pled.{DiffFormatter, Sync, UI}

  def help do
    IO.puts("""
    Usage:
      pled check-remote [options]

    Description:
      Compares the baseline, locally built plugin, and current Bubble plugin.
      Reports whether the workspace is in sync, local ahead, remote ahead, or
      diverged without making changes.

    Options:
      --verbose, -v    Show detailed output
      --help, -h       Show this help message

    Examples:
      pled check-remote        Check the three-way sync state
      pled check-remote -v     Check with detailed change paths
    """)

    :ok
  end

  def run(opts \\ []) do
    verbose? = Keyword.get(opts, :verbose, false)

    case Sync.status() do
      {:ok, sync} ->
        IO.puts(DiffFormatter.format_sync(sync, detailed: verbose?))
        :ok

      {:error, reason} ->
        IO.puts(
          IO.ANSI.red() <>
            "✗ Failed to determine sync status: #{UI.format_reason(reason)}" <> IO.ANSI.reset()
        )

        {:error, reason}
    end
  end
end
