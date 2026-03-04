defmodule Pled.Commands.Status do
  @moduledoc """
  Command to display environment, authentication, and sync status.
  """
  alias Pled.{PluginDiff, PluginId, RemoteChecker}

  def run(opts \\ []) do
    verbose? = Keyword.get(opts, :verbose, false)

    IO.puts("")
    IO.puts("Environment:")
    env_ok = check_environment()

    IO.puts("")
    IO.puts("Authentication:")

    if env_ok do
      case check_authentication() do
        :ok ->
          IO.puts("  " <> IO.ANSI.green() <> "✓ Cookie is valid" <> IO.ANSI.reset())
          IO.puts("")
          IO.puts("Sync Status:")
          check_sync_status(verbose?)

        {:error, reason} ->
          IO.puts("  " <> IO.ANSI.red() <> "✗ Cookie is invalid or expired" <> IO.ANSI.reset())

          if verbose? do
            IO.puts("    #{reason}")
          end

          {:error, :auth_failed}
      end
    else
      IO.puts(
        "  " <>
          IO.ANSI.yellow() <> "⚠ Cannot verify (missing environment variables)" <> IO.ANSI.reset()
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

  defp check_authentication do
    case Pled.BubbleApi.fetch_plugin() do
      {:ok, _plugin_data} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_sync_status(verbose?) do
    if RemoteChecker.snapshot_exists?() do
      case RemoteChecker.check_remote_changes() do
        :no_changes ->
          IO.puts("  " <> IO.ANSI.green() <> "✓ Local matches remote" <> IO.ANSI.reset())
          :ok

        {:changes_detected, %PluginDiff{} = diff} ->
          IO.puts("  " <> IO.ANSI.yellow() <> "⚠ Local differs from remote" <> IO.ANSI.reset())
          print_summary(diff.summary)

          if verbose? do
            IO.puts("")
            print_detailed_changes(diff.changes)
          end

          :ok

        {:error, reason} ->
          IO.puts("  " <> IO.ANSI.red() <> "✗ Failed to check: #{reason}" <> IO.ANSI.reset())
          {:error, reason}
      end
    else
      IO.puts(
        "  " <>
          IO.ANSI.yellow() <> "⚠ No baseline found (run 'pled pull' first)" <> IO.ANSI.reset()
      )

      :ok
    end
  end

  defp print_summary(summary) when map_size(summary) == 0, do: :ok

  defp print_summary(summary) do
    summary
    |> Enum.sort_by(fn {type, _count} -> Atom.to_string(type) end)
    |> Enum.each(fn {type, count} ->
      IO.puts("    • #{count} × #{humanize_type(type)}")
    end)
  end

  defp print_detailed_changes(changes) do
    IO.puts("  Detailed changes:")

    changes
    |> Enum.with_index(1)
    |> Enum.each(fn {change, idx} ->
      IO.puts("    #{idx}. #{describe_change(change)}")
    end)
  end

  defp describe_change(%PluginDiff.Change{} = change) do
    location = Enum.join(change.path, ".")
    "[#{humanize_type(change.type)}] #{location}"
  end

  defp humanize_type(type) do
    type
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
