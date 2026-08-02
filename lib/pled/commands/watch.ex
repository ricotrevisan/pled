defmodule Pled.Commands.Watch do
  @moduledoc """
  Runs the conflict-aware watch loop until interrupted.
  """
  alias Pled.{FileWatcher, Sync, UI}

  def help do
    IO.puts("""
    Usage:
      pled watch [options]

    Description:
      Watches the src/ directory and keeps it in sync with Bubble. Local edits
      are pushed when the remote is clean, remote changes are pulled when
      nothing local is unpushed, and watch pauses with a conflict banner when
      both sides changed. Press Ctrl+C to stop.

    Options:
      --interval, -i   Seconds between remote checks (default 15)
      --verbose, -v    Show detailed output
      --help, -h       Show this help message

    Examples:
      pled watch             Start watching for changes
      pled watch -v          Watch with verbose output
      pled watch -i 60       Check Bubble once a minute
    """)

    :ok
  end

  def run(opts \\ []) do
    verbose? = Keyword.get(opts, :verbose, false)

    with :ok <- check_workspace(),
         {:ok, watcher_opts} <- watcher_opts(opts),
         {:ok, _pid} <- FileWatcher.start_link(watcher_opts) do
      UI.logo()

      IO.puts(
        "Watching #{FileWatcher.src_dir()}/ for changes; polling Bubble for remote changes."
      )

      UI.info("Press Ctrl+C to stop.", verbose?)
      Process.sleep(:infinity)
    else
      {:error, reason} when is_atom(reason) ->
        {:error, reason}

      {:error, reason} ->
        UI.error("✗ Failed to start the file watcher: #{UI.format_reason(reason)}")
        {:error, reason}
    end
  end

  defp check_workspace do
    cond do
      not File.dir?(FileWatcher.src_dir()) ->
        UI.error("✗ No #{FileWatcher.src_dir()}/ directory found. Run `pled pull` first.")
        {:error, :no_src}

      not File.exists?(Sync.baseline_path()) ->
        UI.error("✗ No baseline snapshot at #{Sync.baseline_path()}. Run `pled pull` first.")
        {:error, :no_baseline}

      true ->
        :ok
    end
  end

  defp watcher_opts(opts) do
    watcher_opts = Keyword.take(opts, [:verbose])

    case Keyword.get(opts, :interval) do
      nil ->
        {:ok, watcher_opts}

      seconds when seconds > 0 ->
        {:ok, Keyword.put(watcher_opts, :poll_interval_ms, seconds * 1000)}

      _seconds ->
        UI.error("✗ --interval must be at least 1 second.")
        {:error, :invalid_interval}
    end
  end
end
