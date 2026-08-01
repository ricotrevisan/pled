defmodule Pled.DiffFormatter do
  @moduledoc """
  Shared user-facing formatting for canonical plugin diffs and sync states.
  """

  alias Pled.{PluginDiff, Sync}

  @doc """
  Formats a structured plugin diff.

  Pass `detailed: true` to include each changed path and value preview.
  """
  @spec format(PluginDiff.t(), keyword()) :: String.t()
  def format(%PluginDiff{} = diff, opts \\ []) do
    detailed? = Keyword.get(opts, :detailed, false)

    summary_lines =
      if map_size(diff.summary) == 0 do
        ["Summary:", "  (no structured changes detected)"]
      else
        lines =
          diff.summary
          |> Enum.sort_by(fn {type, _count} -> Atom.to_string(type) end)
          |> Enum.map(fn {type, count} ->
            "  • #{count} × #{humanize_type(type)}"
          end)

        ["Summary:" | lines]
      end

    detailed_lines =
      if detailed? do
        changes =
          diff.changes
          |> Enum.with_index(1)
          |> Enum.map(fn {change, index} ->
            "  #{index}. #{describe_change(change)}"
          end)

        ["", "Detailed changes:" | changes]
      else
        []
      end

    Enum.join(summary_lines ++ detailed_lines, "\n")
  end

  @doc """
  Formats a complete sync result, including its exact next command.
  """
  @spec format_sync(
          %{
            optional(atom()) => term(),
            state: Sync.state(),
            diffs: %{optional(:local | :remote) => PluginDiff.t()},
            issues: [map()]
          },
          keyword()
        ) :: String.t()
  def format_sync(sync, opts \\ []) do
    [format_state(sync, opts), format_issues(sync)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp format_state(%{state: :in_sync}, _opts) do
    "✓ In sync\nNext: No action needed."
  end

  defp format_state(%{state: :local_ahead, diffs: %{local: diff}}, opts) do
    Enum.join(
      ["⚠ Local ahead", "Local changes:", format(diff, diff_options(opts)), "Next: `pled push`"],
      "\n"
    )
  end

  defp format_state(%{state: :remote_ahead, diffs: %{remote: diff}}, opts) do
    Enum.join(
      [
        "⚠ Remote ahead",
        "Remote changes:",
        format(diff, diff_options(opts)),
        "Next: `pled pull`"
      ],
      "\n"
    )
  end

  defp format_state(
         %{state: :diverged, diffs: %{local: local_diff, remote: remote_diff}},
         opts
       ) do
    Enum.join(
      [
        "✗ Diverged: local and remote both changed",
        "Local changes:",
        format(local_diff, diff_options(opts)),
        "Remote changes:",
        format(remote_diff, diff_options(opts)),
        "Next: choose one:",
        "  • `pled pull --wipe` — discard local changes",
        "  • `pled push --force` — overwrite remote changes"
      ],
      "\n"
    )
  end

  defp format_state(%{state: :no_baseline}, _opts) do
    "⚠ No baseline\nNext: `pled pull` to create a baseline before syncing."
  end

  defp format_issues(%{issues: []}), do: nil

  defp format_issues(%{issues: issues}) do
    count = length(issues)

    "Note: the local build has #{count} validation #{if count == 1, do: "issue", else: "issues"}. " <>
      "Run `pled encode` to review and confirm them before pushing."
  end

  defp diff_options(opts) do
    [detailed: Keyword.get(opts, :detailed, false)]
  end

  defp describe_change(%PluginDiff.Change{} = change) do
    location = Enum.join(change.path, ".")

    "[#{humanize_type(change.type)}] #{location}: " <>
      "#{preview(change.before)} → #{preview(change.after)}"
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
