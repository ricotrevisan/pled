defmodule Pled.DiffFormatterTest do
  use ExUnit.Case, async: true

  alias Pled.{DiffFormatter, PluginDiff}

  test "formats a stable summary and optional details" do
    diff = PluginDiff.diff(%{"name" => "Before"}, %{"name" => "After"})

    assert DiffFormatter.format(diff) == "Summary:\n  • 1 × Metadata field changed"

    detailed = DiffFormatter.format(diff, detailed: true)
    assert detailed =~ "Detailed changes:"
    assert detailed =~ ~s([Metadata field changed] metadata.name: "Before" → "After")
  end

  test "formats next-step guidance and local validation issues" do
    diff = PluginDiff.diff(%{"name" => "Before"}, %{"name" => "After"})

    output =
      DiffFormatter.format_sync(%{
        state: :local_ahead,
        diffs: %{local: diff},
        issues: [%{type: :field_caption_change}]
      })

    assert output =~ "Local ahead"
    assert output =~ "Next: `pled push`"
    assert output =~ "1 validation issue"
    assert output =~ "`pled encode`"
  end
end
