defmodule Pled.FileWatcher do
  @moduledoc """
  GenServer that watches the src/ directory for changes to JavaScript files
  and automatically runs `pled push` when changes are detected.
  """
  use GenServer

  @debounce_ms 500
  @remote_check_interval_ms 2000
  @src_dir "src"

  defstruct [:watcher_pid, :debounce_timer, :remote_check_timer]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def stop do
    GenServer.stop(__MODULE__)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    if File.exists?(@src_dir) do
      dir = Path.join(File.cwd!(), @src_dir)

      {:ok, watcher_pid} = FileSystem.start_link(dirs: [dir], name: :file_watcher)
      FileSystem.subscribe(:file_watcher)

      # Start periodic remote checking
      remote_timer = Process.send_after(self(), :check_remote, @remote_check_interval_ms)

      state = %{
        watcher_pid: watcher_pid,
        directory_path: dir,
        debounce_timer: nil,
        remote_check_timer: remote_timer
      }

      {:ok, state}
    else
      {:error, "#{@src_dir} directory does not exist"}
    end
  end

  @impl true
  def handle_info({:file_event, watcher_pid, {path, events}}, %{watcher_pid: watcher_pid} = state) do
    if should_handle_file?(path, events) do
      IO.puts("File changed: #{path}")

      # Cancel any existing debounce timer
      if state.debounce_timer do
        Process.cancel_timer(state.debounce_timer)
      end

      # Set new debounce timer
      timer = Process.send_after(self(), :run_push, @debounce_ms)
      {:noreply, %{state | debounce_timer: timer}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:file_event, watcher_pid, :stop}, %{watcher_pid: watcher_pid} = state) do
    IO.puts("File watcher stopped")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:run_push, state) do
    # Wrap in try/catch to handle any unexpected errors
    try do
      case Pled.Commands.Push.run(force: true) do
        :ok ->
          :ok

        {:error, reason} ->
          # Use inspect to safely display any error type
          IO.puts("Push failed: #{format_error(reason)} - retrying on next change")
      end
    catch
      kind, reason ->
        IO.puts("Push failed with #{kind}: #{inspect(reason)} - retrying on next change")
    end

    {:noreply, %{state | debounce_timer: nil}}
  end

  @impl true
  def handle_info(:check_remote, state) do
    # Check for remote changes and pull if needed
    try do
      case Pled.RemoteChecker.check_remote_changes() do
        :no_changes ->
          :ok

        {:changes_detected, %Pled.PluginDiff{} = diff} ->
          IO.puts("")

          IO.puts(
            IO.ANSI.cyan() <> "🔄 Remote changes detected during watch mode" <> IO.ANSI.reset()
          )

          format_remote_changes(diff)
          IO.puts("Pulling remote changes...")

          case Pled.Commands.Pull.run([]) do
            :ok ->
              IO.puts(
                IO.ANSI.green() <> "✓ Remote changes pulled successfully" <> IO.ANSI.reset()
              )

            {:error, reason} ->
              IO.puts(
                IO.ANSI.red() <>
                  "✗ Failed to pull remote changes: #{inspect(reason)}" <> IO.ANSI.reset()
              )
          end

        {:error, _reason} ->
          # Silently ignore remote check errors in watch mode
          :ok
      end
    catch
      _kind, _reason ->
        # Silently ignore any errors during remote checking in watch mode
        :ok
    end

    # Schedule next remote check
    remote_timer = Process.send_after(self(), :check_remote, @remote_check_interval_ms)
    {:noreply, %{state | remote_check_timer: remote_timer}}
  end

  @impl true
  def handle_info(msg, state) do
    IO.puts(IO.ANSI.red() <> "Unhandled message: #{inspect(msg)}\nstate: #{inspect(state)}")

    {:noreply, state}
  end

  @impl true
  def terminate(reason, %{watcher_pid: watcher_pid}) when is_pid(watcher_pid) do
    GenServer.stop(watcher_pid)
    IO.puts("FileWatcher terminated: #{inspect(reason)}")
    :ok
  end

  @impl true
  def terminate(reason, _state) do
    IO.puts("FileWatcher terminated: #{inspect(reason)}")
    :ok
  end

  # Private functions

  defp should_handle_file?(_path, events) do
    has_relevant_events?(events)
  end

  defp has_relevant_events?(events) do
    relevant_events = [:created, :modified, :removed]
    Enum.any?(events, &(&1 in relevant_events))
  end

  # Helper to format errors for display
  defp format_error(%Req.TransportError{reason: reason}),
    do: "Transport error: #{inspect(reason)}"

  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)

  defp format_remote_changes(%Pled.PluginDiff{} = diff) do
    diff.summary
    |> Enum.sort_by(fn {type, _count} -> Atom.to_string(type) end)
    |> Enum.each(fn {type, count} ->
      type_label =
        type |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

      IO.puts("  • #{count} × #{type_label}")
    end)
  end
end
