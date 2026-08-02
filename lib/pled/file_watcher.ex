defmodule Pled.FileWatcher do
  @moduledoc """
  Watches `src/` and keeps it in sync with Bubble through `Pled.Sync`.

  Every cycle — triggered by a debounced file change or by the remote poll —
  classifies the workspace and acts on the result: local edits are pushed only
  while the remote is clean, remote changes are pulled only while nothing local
  is unpushed, and a divergence puts the watcher on hold until a human resolves
  it. Nothing here ever prompts or forces.
  """
  use GenServer

  alias Pled.Commands.{Pull, Push}
  alias Pled.{DiffFormatter, Sync, UI}

  @src_dir "src"
  @debounce_ms 500
  @poll_interval_ms 15_000
  @max_poll_interval_ms 120_000
  @pull_settle_ms 1_000
  @relevant_events [:created, :modified, :removed]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the only directory watch cares about.
  """
  def src_dir, do: @src_dir

  @impl true
  def init(opts) do
    dir = Path.join(File.cwd!(), @src_dir)

    case FileSystem.start_link(dirs: [dir]) do
      {:ok, watcher_pid} ->
        FileSystem.subscribe(watcher_pid)
        {:ok, schedule_poll(initial_state(watcher_pid, opts))}

      other ->
        {:stop,
         {:shutdown,
          "Could not watch #{dir} (#{inspect(other)}). " <>
            "On Linux this usually means `inotify-tools` is not installed."}}
    end
  end

  defp initial_state(watcher_pid, opts) do
    %{
      watcher_pid: watcher_pid,
      debounce_timer: nil,
      poll_timer: nil,
      hold?: false,
      error_count: 0,
      suppress_until: now_ms(),
      verbose?: Keyword.get(opts, :verbose, false),
      debounce_ms: Keyword.get(opts, :debounce_ms, @debounce_ms),
      poll_interval_ms: configured_poll_interval(opts),
      pull_settle_ms: Keyword.get(opts, :pull_settle_ms, @pull_settle_ms)
    }
  end

  @impl true
  def handle_info({:file_event, pid, {path, events}}, %{watcher_pid: pid} = state) do
    if relevant?(events) and not suppressed?(state) do
      IO.puts("File changed: #{path}")
      {:noreply, schedule_debounce(state)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:file_event, pid, :stop}, %{watcher_pid: pid} = state) do
    IO.puts("File watcher stopped")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:debounce, state) do
    state = %{state | debounce_timer: nil}
    {:noreply, state |> run_cycle() |> schedule_poll()}
  end

  @impl true
  def handle_info(:poll, state) do
    # A pending debounce owns the next cycle; pushing mid-edit helps nobody.
    state = if state.debounce_timer, do: state, else: run_cycle(state)
    {:noreply, schedule_poll(state)}
  end

  @impl true
  def handle_info(msg, state) do
    UI.error("Unhandled message: #{inspect(msg)}")
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

  defp run_cycle(state) do
    {new_state, action, sync_state} =
      try do
        case Sync.status() do
          {:ok, sync} ->
            {new_state, action} = apply_sync(sync, state)
            {reset_backoff(new_state, action), action, sync.state}

          {:error, reason} ->
            {failure(reason, state), :failed, :unknown}
        end
      catch
        kind, reason ->
          {failure({kind, reason}, state), :failed, :unknown}
      end

    UI.info(
      "[watch] state=#{sync_state} action=#{action} hold=#{new_state.hold?}",
      state.verbose?
    )

    new_state
  end

  defp reset_backoff(state, :failed), do: state
  defp reset_backoff(state, _action), do: %{state | error_count: 0}

  defp apply_sync(%{state: :diverged} = sync, state), do: hold(sync, state)

  defp apply_sync(sync, state) do
    state = resume(state)

    case sync.state do
      :in_sync -> {state, :none}
      :local_ahead -> push(sync, state)
      :remote_ahead -> pull(sync, state)
      :no_baseline -> baseline_missing(state)
    end
  end

  defp push(sync, state) do
    case Push.run(sync: sync, interactive: false, verbose: state.verbose?) do
      :ok ->
        {state, :pushed}

      {:error, :unresolved_issues} ->
        UI.error("Push skipped: fix the validation issues above, then save again.")
        {state, :skipped}

      {:error, reason} ->
        {failure(reason, state), :failed}
    end
  end

  defp pull(sync, state) do
    IO.puts(IO.ANSI.cyan() <> "🔄 Remote changes detected" <> IO.ANSI.reset())
    IO.puts(DiffFormatter.format(sync.diffs.remote, detailed: state.verbose?))

    case Pull.run(sync: sync, verbose: state.verbose?) do
      :ok ->
        IO.puts(IO.ANSI.green() <> "✓ Remote changes pulled" <> IO.ANSI.reset())
        {suppress_own_writes(state), :pulled}

      {:error, reason} ->
        {failure(reason, state), :failed}
    end
  end

  defp hold(_sync, %{hold?: true} = state), do: {state, :holding}

  defp hold(sync, state) do
    IO.puts("")
    IO.puts(IO.ANSI.red() <> "⛔ Watch paused: local and remote both changed." <> IO.ANSI.reset())
    IO.puts(DiffFormatter.format_sync(sync, detailed: state.verbose?))
    IO.puts("Watch will not push or pull until this is resolved, then it resumes on its own.")
    {%{state | hold?: true}, :held}
  end

  defp resume(%{hold?: true} = state) do
    IO.puts(IO.ANSI.green() <> "✓ Divergence resolved; watch resuming." <> IO.ANSI.reset())
    %{state | hold?: false}
  end

  defp resume(state), do: state

  defp baseline_missing(state) do
    UI.error("✗ No baseline snapshot at #{Sync.baseline_path()}. Run `pled pull` to recreate it.")

    {state, :blocked}
  end

  defp failure(reason, state) do
    message = UI.format_reason(reason)

    if auth_error?(reason, message) do
      UI.error("⚠ Bubble rejected the request as unauthorized: #{message}")
      UI.error("⚠ Refresh BUBBLE_COOKIE; watch keeps retrying until it works.")
    else
      UI.error("✗ Sync failed: #{message}")
    end

    # Clamped so a watcher left running through a long outage keeps the shift small.
    %{state | error_count: min(state.error_count + 1, 16)}
  end

  defp auth_error?({:unauthorized, _reason}, _message), do: true
  defp auth_error?(_reason, message), do: String.contains?(message, "HTTP 401")

  defp suppress_own_writes(state) do
    if state.debounce_timer, do: Process.cancel_timer(state.debounce_timer)

    %{
      state
      | debounce_timer: nil,
        suppress_until: now_ms() + state.pull_settle_ms
    }
  end

  defp suppressed?(state), do: now_ms() < state.suppress_until

  defp relevant?(events), do: Enum.any?(events, &(&1 in @relevant_events))

  defp schedule_debounce(state) do
    if state.debounce_timer, do: Process.cancel_timer(state.debounce_timer)
    %{state | debounce_timer: Process.send_after(self(), :debounce, state.debounce_ms)}
  end

  defp schedule_poll(state) do
    if state.poll_timer, do: Process.cancel_timer(state.poll_timer)
    %{state | poll_timer: Process.send_after(self(), :poll, poll_delay(state))}
  end

  defp poll_delay(%{error_count: 0} = state), do: state.poll_interval_ms

  defp poll_delay(state) do
    backoff = state.poll_interval_ms * Integer.pow(2, state.error_count)
    min(backoff, @max_poll_interval_ms)
  end

  defp configured_poll_interval(opts) do
    Keyword.get_lazy(opts, :poll_interval_ms, fn ->
      Application.get_env(:pled, :watch_poll_interval_ms, @poll_interval_ms)
    end)
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
