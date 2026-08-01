defmodule Pled.Commands.Status do
  @moduledoc """
  Command to display environment, remote reachability, and sync status.
  """

  alias Pled.{DiffFormatter, PluginId, Sync}

  def help do
    IO.puts("""
    Usage:
      pled status [options]

    Description:
      Displays environment configuration, remote reachability, and the
      three-way sync state of the baseline, local source, and Bubble plugin.

    Options:
      --verbose, -v    Show detailed output (includes detailed change list)
      --help, -h       Show this help message

    Examples:
      pled status            Show current status
      pled status -v         Show status with detailed change information
    """)

    :ok
  end

  def run(opts \\ []) do
    verbose? = Keyword.get(opts, :verbose, false)

    IO.puts("")
    IO.puts("Environment:")
    env_ok = check_environment()

    IO.puts("")
    IO.puts("Remote:")

    if env_ok do
      check_sync_status(verbose?)
    else
      IO.puts(
        "  " <>
          IO.ANSI.yellow() <>
          "⚠ Cannot check remote (missing environment variables)" <> IO.ANSI.reset()
      )

      {:error, :missing_env}
    end
  end

  defp check_environment do
    plugin_id_ok =
      case PluginId.load() do
        {:ok, id} ->
          {_, source} = PluginId.source()
          label = if source == :file, do: "from .plugin_id", else: "from env var"
          IO.puts("  " <> IO.ANSI.green() <> "✓ PLUGIN_ID: #{id} (#{label})" <> IO.ANSI.reset())
          true

        {:error, _} ->
          IO.puts("  " <> IO.ANSI.red() <> "✗ PLUGIN_ID not found" <> IO.ANSI.reset())
          IO.puts("    Run 'pled init <bubble-plugin-url>' or set PLUGIN_ID env var.")
          false
      end

    cookie_ok =
      case System.get_env("BUBBLE_COOKIE") do
        nil ->
          IO.puts("  " <> IO.ANSI.red() <> "✗ BUBBLE_COOKIE is not set" <> IO.ANSI.reset())
          false

        cookie ->
          IO.puts(
            "  " <>
              IO.ANSI.green() <>
              "✓ BUBBLE_COOKIE is set (#{String.length(cookie)} chars)" <> IO.ANSI.reset()
          )

          true
      end

    plugin_id_ok and cookie_ok
  end

  defp check_sync_status(verbose?) do
    case Sync.status() do
      {:ok, sync} ->
        print_remote_reachable()
        IO.puts("")
        IO.puts("Sync Status:")
        IO.puts(DiffFormatter.format_sync(sync, detailed: verbose?))
        :ok

      {:error, {:remote_unreachable, reason} = error} ->
        IO.puts("  " <> IO.ANSI.red() <> "✗ Could not fetch remote plugin" <> IO.ANSI.reset())
        if verbose?, do: IO.puts("    #{reason}")
        {:error, error}

      {:error, reason} ->
        print_remote_reachable()
        IO.puts("")
        IO.puts("Sync Status:")
        IO.puts("  " <> IO.ANSI.red() <> "✗ Could not determine sync status" <> IO.ANSI.reset())
        IO.puts("    #{reason}")
        {:error, reason}
    end
  end

  defp print_remote_reachable do
    IO.puts(
      "  " <>
        IO.ANSI.green() <>
        "✓ Remote plugin is reachable (edit permission is checked on push)" <>
        IO.ANSI.reset()
    )
  end
end
