defmodule Pled.Commands.Pull do
  @moduledoc """
  Fetches the remote plugin and rewrites the local source tree from it.

  The three-way sync state guards the overwrite: unpushed local work is only
  discarded when `--wipe` states that intent explicitly. Watch passes its
  already-computed status as the `:sync` option to avoid a second fetch.
  """

  alias Pled.Commands.Decoder
  alias Pled.{BubbleApi, DiffFormatter, Sync, UI}

  def help do
    IO.puts("""
    Usage:
      pled pull [options]

    Description:
      Fetches the plugin data from Bubble.io and decodes it into local files
      under the src/ directory. Entities deleted or renamed in Bubble are
      removed locally, and the baseline snapshot is rewritten on success.
      Unpushed local changes block the pull unless --wipe is given.

    Options:
      --wipe, -w       Discard local changes: remove src/ and dist/ before pulling
      --verbose, -v    Show detailed output
      --help, -h       Show this help message

    Examples:
      pled pull              Fetch and decode plugin files
      pled pull --wipe       Discard local changes and pull
      pled pull -w -v        Wipe and pull with verbose output
    """)

    :ok
  end

  def run(opts) do
    verbose? = Keyword.get(opts, :verbose, false)
    wipe? = Keyword.get(opts, :wipe, false)

    IO.puts("pulling")
    UI.info("Fetching plugin from Bubble.io...", verbose?)

    case authorize(wipe?, opts) do
      {:ok, plugin_data} ->
        write_plugin(plugin_data, wipe?, verbose?)

      {:reported, reason} ->
        {:error, reason}

      {:error, reason} ->
        pull_error(reason)
    end
  end

  defp authorize(true, _opts), do: BubbleApi.fetch_plugin()

  defp authorize(false, opts) do
    # Without src/plugin.json nothing local can be built, so there is nothing to protect.
    if File.exists?(Path.join("src", "plugin.json")) do
      guard(opts)
    else
      BubbleApi.fetch_plugin()
    end
  end

  defp guard(opts) do
    case Sync.status(opts) do
      {:ok, %{state: state} = sync} when state in [:local_ahead, :diverged] ->
        IO.puts(DiffFormatter.format_sync(sync, detailed: Keyword.get(opts, :verbose, false)))
        IO.puts("Pull refused to protect unpushed local changes.")
        IO.puts("Push them first, or run `pled pull --wipe` to discard them.")
        {:reported, state}

      {:ok, sync} ->
        {:ok, sync.remote}

      {:error, {:remote_unreachable, _} = reason} ->
        {:error, reason}

      {:error, reason} ->
        pull_error(reason)
        IO.puts("If the local source tree is broken, `pled pull --wipe` rebuilds it from Bubble.")
        {:reported, reason}
    end
  end

  defp write_plugin(plugin_data, wipe?, verbose?) do
    with :ok <- wipe(wipe?, verbose?),
         :ok <- write_plugin_json(plugin_data, verbose?),
         :ok <- Decoder.decode(plugin_data, File.cwd!()) do
      save_baseline(plugin_data, verbose?)
      IO.puts("Pull completed")
      :ok
    else
      {:error, reason} -> pull_error(reason)
    end
  end

  defp wipe(false, _verbose?), do: :ok

  defp wipe(true, verbose?) do
    UI.info("Wiping src and dist directories...", verbose?)

    with {:ok, dist} <- File.rm_rf("dist"),
         {:ok, src} <- File.rm_rf("src") do
      UI.info("removed:", verbose?)
      Enum.each(dist ++ src, &UI.info(&1, verbose?))
      :ok
    else
      {:error, reason, file} ->
        {:error, "Failed to remove #{file}: #{:file.format_error(reason)}"}
    end
  end

  defp write_plugin_json(plugin_data, verbose?) do
    File.mkdir_p!("src")
    plugin_file = Path.join("src", "plugin.json")

    case File.write(plugin_file, Jason.encode!(plugin_data, pretty: true)) do
      :ok ->
        UI.info("Plugin data saved to #{plugin_file}", verbose?)
        :ok

      {:error, reason} ->
        {:error, "Failed to write #{plugin_file}: #{:file.format_error(reason)}"}
    end
  end

  defp save_baseline(plugin_data, verbose?) do
    case Sync.save_baseline(plugin_data) do
      :ok ->
        UI.info("Baseline snapshot saved", verbose?)

      {:error, reason} ->
        IO.puts(
          IO.ANSI.yellow() <>
            "⚠ Plugin pulled, but the baseline was not updated: #{reason}. " <>
            "Run `pled pull` again before pushing." <> IO.ANSI.reset()
        )
    end
  end

  defp pull_error(reason) do
    IO.puts("Pull failed: #{UI.format_reason(reason)}")
    {:error, reason}
  end
end
