defmodule Pled.Commands.Push do
  @moduledoc """
  Uploads the local plugin when the three-way sync state permits it.

  Watch temporarily passes the internal `:sync` option as `false` to retain
  its legacy RemoteChecker guard until conflict-aware watch mode lands.
  """

  alias Pled.Commands.Encoder
  alias Pled.{BubbleApi, DiffFormatter, Prompt, RemoteChecker, Sync, UI}

  def help do
    IO.puts("""
    Usage:
      pled push [options]

    Description:
      Builds the local plugin, compares it with the baseline and Bubble, and
      uploads only when doing so is safe. Remote changes require an explicit
      --force override; Bubble must remain reachable for the safety check.

    Options:
      --force, -f      Intentionally overwrite remote changes
      --verbose, -v    Show detailed output
      --help, -h       Show this help message

    Examples:
      pled push              Push local changes when safe
      pled push --force      Intentionally overwrite remote changes
      pled push -f -v        Force push with detailed change output
    """)

    :ok
  end

  def run(opts) do
    IO.puts("pushing")

    if Keyword.get(opts, :sync, true) do
      run_guarded(opts)
    else
      run_legacy(opts)
    end
  end

  defp run_guarded(opts) do
    force? = Keyword.get(opts, :force, false)

    case Sync.status() do
      {:ok, %{state: :in_sync} = sync} ->
        IO.puts(DiffFormatter.format_sync(sync, detailed: verbose?(opts)))
        IO.puts("Plugin is already in sync; nothing uploaded.")
        if force?, do: IO.puts("The --force flag was ignored because there is nothing to upload.")
        :ok

      {:ok, sync} ->
        with :ok <- authorize_push(sync, force?, opts),
             :ok <-
               Encoder.confirm_issues(sync.issues,
                 operation: "Push",
                 command: "pled push"
               ),
             :ok <- write_payload(sync.local, opts),
             :ok <- BubbleApi.save_plugin(sync.local) do
          save_baseline_after_push(sync.local)
          IO.puts("Push completed")
          :ok
        else
          {:refused, reason} -> {:error, reason}
          {:error, reason} when reason in [:cancelled, :unresolved_issues] -> {:error, reason}
          {:error, reason} -> push_error(reason)
        end

      {:error, reason} ->
        push_error(reason)
    end
  end

  # Watch keeps its RemoteChecker-based guard until the conflict-aware watch ticket lands.
  defp run_legacy(opts) do
    with :ok <- Encoder.encode(opts),
         :ok <- BubbleApi.save_plugin() do
      _ = RemoteChecker.update_snapshot()
      IO.puts("Push completed")
      :ok
    else
      {:error, reason} -> push_error(reason)
    end
  end

  defp authorize_push(%{state: :local_ahead}, _force?, _opts), do: :ok

  defp authorize_push(%{state: state} = sync, false, opts)
       when state in [:remote_ahead, :diverged] do
    IO.puts(DiffFormatter.format_sync(sync, detailed: verbose?(opts)))
    IO.puts("Push refused to protect remote changes.")
    {:refused, state}
  end

  defp authorize_push(%{state: state, diffs: %{remote: remote_diff}}, true, opts)
       when state in [:remote_ahead, :diverged] do
    IO.puts(
      IO.ANSI.yellow() <> "⚠ Force push will discard these remote changes:" <> IO.ANSI.reset()
    )

    IO.puts(DiffFormatter.format(remote_diff, detailed: verbose?(opts)))
    :ok
  end

  defp authorize_push(%{state: :no_baseline}, true, _opts) do
    IO.puts(
      IO.ANSI.yellow() <>
        "⚠ Force pushing without a baseline; existing remote changes may be discarded." <>
        IO.ANSI.reset()
    )

    :ok
  end

  defp authorize_push(%{state: :no_baseline}, false, _opts) do
    IO.puts(IO.ANSI.yellow() <> "⚠ No baseline found." <> IO.ANSI.reset())

    if Prompt.interactive?() do
      if Prompt.confirm?("Push without a baseline? This may overwrite remote work. [y/N]: ") do
        :ok
      else
        IO.puts("Push cancelled; nothing was uploaded.")
        {:refused, :cancelled}
      end
    else
      IO.puts(
        "Push refused in a non-interactive session. Run `pled pull` first or use `pled push --force`."
      )

      {:refused, :no_baseline}
    end
  end

  defp write_payload(payload, opts) do
    case Encoder.write_dist(payload, opts) do
      :ok ->
        IO.puts("dist/plugin.json generated")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp save_baseline_after_push(payload) do
    case Sync.save_baseline(payload) do
      :ok ->
        :ok

      {:error, reason} ->
        IO.puts(
          IO.ANSI.yellow() <>
            "⚠ Plugin uploaded, but the baseline was not updated: #{reason}. " <>
            "Run `pled status` before your next push." <>
            IO.ANSI.reset()
        )
    end
  end

  defp push_error(reason) do
    IO.puts("Push failed: #{UI.format_reason(reason)}")
    {:error, reason}
  end

  defp verbose?(opts), do: Keyword.get(opts, :verbose, false)
end
