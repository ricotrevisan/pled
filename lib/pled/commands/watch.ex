defmodule Pled.Commands.Watch do
  @moduledoc """
  Command to start the file watcher that automatically runs `pled push`
  when JavaScript files in the src/ directory are changed.
  """
  alias Pled.UI

  def help do
    IO.puts("""
    Usage:
      pled watch [options]

    Description:
      Watches the src/ directory for file changes and automatically encodes
      and pushes the plugin to Bubble.io on each change. Press Ctrl+C to stop.

    Options:
      --verbose, -v    Show detailed output
      --help, -h       Show this help message

    Examples:
      pled watch             Start watching for changes
      pled watch -v          Watch with verbose output
    """)

    :ok
  end

  def run(opts \\ []) do
    verbose? = Keyword.get(opts, :verbose, false)

    try do
      case Pled.FileWatcher.start_link() do
        {:ok, _pid} ->
          UI.logo()
          IO.puts("Started file watcher")
          # Keep the process alive until terminated (Ctrl+C)
          Process.sleep(:infinity)

        {:error, {:already_started, _pid}} ->
          IO.puts("Started file watcher")
          UI.info("File watcher is already running", verbose?)
          Process.sleep(:infinity)

        {:error, reason} ->
          IO.puts("Watch failed: #{inspect(reason)}")
          {:error, "Failed to start file watcher: #{inspect(reason)}"}
      end
    catch
      kind, reason ->
        IO.puts("Watch failed with #{kind}: #{inspect(reason)}")
        {:error, "Failed to start file watcher: #{inspect(reason)}"}
    end
  end
end
