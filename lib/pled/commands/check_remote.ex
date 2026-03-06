defmodule Pled.Commands.CheckRemote do
  @moduledoc """
  Command to check for remote changes without pushing.
  """
  alias Pled.{PluginDiff, RemoteChecker}

  def help do
    IO.puts("""
    Usage:
      pled check-remote [options]

    Description:
      Compares the local plugin snapshot with the current remote version on
      Bubble.io. Reports any differences without making changes. Useful for
      checking if someone has edited the plugin in Bubble since your last pull.

    Options:
      --verbose, -v    Show detailed output
      --help, -h       Show this help message

    Examples:
      pled check-remote        Check for remote changes
      pled check-remote -v     Check with verbose output
    """)

    :ok
  end

  def run(opts \\ []) do
    _verbose? = Keyword.get(opts, :verbose, false)

    case RemoteChecker.check_remote_changes() do
      :no_changes ->
        IO.puts(IO.ANSI.green() <> "✓ No remote changes detected" <> IO.ANSI.reset())
        :ok

      {:changes_detected, %PluginDiff{} = diff} ->
        IO.puts(IO.ANSI.yellow() <> "⚠ Remote changes detected!" <> IO.ANSI.reset())
        IO.puts("The following changes were found in the remote plugin:")
        IO.puts("")

        format_changes(diff)

        IO.puts("")
        IO.puts("Recommendations:")
        IO.puts("  • Run 'pled pull' to incorporate remote changes")
        IO.puts("  • Or use 'pled push --force' to overwrite remote changes")
        IO.puts("")
        :ok

      {:error, "No local snapshot found. Run 'pled pull' first to create baseline."} ->
        IO.puts(IO.ANSI.yellow() <> "⚠ No baseline found" <> IO.ANSI.reset())
        IO.puts("Run 'pled pull' first to create a baseline for change detection.")
        :ok

      {:error, reason} ->
        IO.puts(IO.ANSI.red() <> "✗ Failed to check remote changes: #{reason}" <> IO.ANSI.reset())
        {:error, reason}
    end
  end

  defp format_changes(%PluginDiff{} = diff) do
    print_summary(diff.summary)
    IO.puts("")
    IO.puts("Detailed changes:")

    diff.changes
    |> Enum.with_index(1)
    |> Enum.each(fn {change, idx} ->
      IO.puts("  #{idx}. #{describe_change(change)}")
    end)
  end

  defp print_summary(summary) when map_size(summary) == 0 do
    IO.puts("(no structured changes detected)")
  end

  defp print_summary(summary) do
    IO.puts("Summary:")

    summary
    |> Enum.sort_by(fn {type, _count} -> Atom.to_string(type) end)
    |> Enum.each(fn {type, count} ->
      IO.puts("  • #{count} × #{humanize_type(type)}")
    end)
  end

  defp describe_change(%PluginDiff.Change{} = change) do
    location = Enum.join(change.path, ".")

    "[#{humanize_type(change.type)}] #{location}: #{preview(change.before)} → #{preview(change.after)}"
  end

  defp humanize_type(type) do
    type
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp preview(nil), do: "∅"

  defp preview(value) when is_binary(value) do
    value
    |> String.replace("\n", "\\n")
    |> truncate(60)
    |> inspect()
  end

  defp preview(value) do
    inspect(value, limit: 3, printable_limit: 80, width: 0)
  end

  defp truncate(value, max) when byte_size(value) <= max, do: value
  defp truncate(value, max), do: String.slice(value, 0, max) <> "…"
end
