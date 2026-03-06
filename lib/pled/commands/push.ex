defmodule Pled.Commands.Push do
  alias Pled.Commands.Encoder
  alias Pled.{PluginDiff, RemoteChecker}

  def help do
    IO.puts("""
    Usage:
      pled push [options]

    Description:
      Encodes local source files into the Bubble.io JSON format and uploads
      the plugin data. Before pushing, checks for remote changes to avoid
      overwriting work done in the Bubble editor.

    Options:
      --force, -f      Skip remote change detection and push immediately
      --verbose, -v    Show detailed output
      --help, -h       Show this help message

    Examples:
      pled push              Encode and push (with remote change check)
      pled push --force      Push without checking for remote changes
      pled push -f -v        Force push with verbose output
    """)

    :ok
  end

  def run(opts) do
    # verbose? = Keyword.get(opts, :verbose, false)
    force? = Keyword.get(opts, :force, false)
    IO.puts("pushing")

    # Check for remote changes unless --force is used
    with :ok <- if(force?, do: :ok, else: check_remote_changes()),
         :ok <- Encoder.encode(opts),
         :ok <- Pled.BubbleApi.save_plugin() do
      # Update snapshot after successful push
      case RemoteChecker.update_snapshot() do
        :ok -> :ok
        # Don't fail push if snapshot update fails
        {:error, _reason} -> :ok
      end

      IO.puts("Push completed")
      :ok
    else
      :abort ->
        IO.puts("Push aborted by user")
        {:error, "Push aborted by user"}

      {:error, reason} ->
        IO.puts("Push failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp check_remote_changes do
    case RemoteChecker.check_remote_changes() do
      :no_changes ->
        :ok

      {:changes_detected, %PluginDiff{} = diff} ->
        IO.puts("")
        IO.puts(IO.ANSI.yellow() <> "⚠ Remote changes detected!" <> IO.ANSI.reset())
        IO.puts("The following changes were found in the remote plugin:")
        IO.puts("")

        format_changes(diff)

        IO.puts("")
        IO.puts("Options:")
        IO.puts("  1. Pull first to get remote changes: pled pull")
        IO.puts("  2. Force push (overwrites remote): pled push --force")
        IO.puts("  3. Abort this push")
        IO.puts("")

        answer = IO.gets("Continue with push? [y/N]: ") |> String.trim() |> String.downcase()

        case answer do
          "y" -> :ok
          "yes" -> :ok
          _ -> :abort
        end

      {:error, "No local snapshot found. Run 'pled pull' first to create baseline."} ->
        IO.puts("")
        IO.puts(IO.ANSI.yellow() <> "⚠ No baseline found" <> IO.ANSI.reset())
        IO.puts("Run 'pled pull' first to create a baseline for change detection.")
        IO.puts("Or use 'pled push --force' to skip this check.")
        IO.puts("")

        answer =
          IO.gets("Continue with push anyway? [y/N]: ") |> String.trim() |> String.downcase()

        case answer do
          "y" -> :ok
          "yes" -> :ok
          _ -> :abort
        end

      {:error, reason} ->
        IO.puts("")
        IO.puts(IO.ANSI.red() <> "✗ Failed to check remote changes: #{reason}" <> IO.ANSI.reset())
        IO.puts("Use 'pled push --force' to skip this check.")
        IO.puts("")

        answer =
          IO.gets("Continue with push anyway? [y/N]: ") |> String.trim() |> String.downcase()

        case answer do
          "y" -> :ok
          "yes" -> :ok
          _ -> {:error, reason}
        end
    end
  end

  defp format_changes(%PluginDiff{} = diff) do
    # Print summary
    diff.summary
    |> Enum.sort_by(fn {type, _count} -> Atom.to_string(type) end)
    |> Enum.each(fn {type, count} ->
      IO.puts("  • #{count} × #{humanize_type(type)}")
    end)

    IO.puts("")
    IO.puts("Detailed changes:")

    diff.changes
    |> Enum.with_index(1)
    |> Enum.each(fn {change, idx} ->
      IO.puts("  #{idx}. #{describe_change(change)}")
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
