defmodule Pled.Commands.Encoder do
  @moduledoc """
  Module that turns the local files into Bubble-accepted json.

  `build/1` is the pure build step: it reads the `src/` tree and returns the
  Bubble payload plus any validation issues, without writing files or
  prompting. `write_dist/2` is the thin write step producing
  `dist/plugin.json`. `encode/1` is the interactive command wiring the two
  together: it prompts to confirm issues on a TTY and fails listing them
  otherwise.
  """
  alias Pled.Commands.Encoder.Element
  alias Pled.Commands.Encoder.Action
  alias Pled.Prompt
  alias Pled.UI

  def help do
    IO.puts("""
    Usage:
      pled encode [options]

    Description:
      Compiles local source files from src/ into dist/plugin.json in the
      Bubble.io JSON format. This is the encoding step of the push process,
      run separately when you want to inspect the output without uploading.

    Options:
      --verbose, -v    Show detailed output
      --help, -h       Show this help message

    Examples:
      pled encode            Generate dist/plugin.json from src/ files
      pled encode -v         Encode with verbose output
    """)

    :ok
  end

  def encode(opts \\ []) do
    IO.puts("encoding")

    if not File.exists?("src/") do
      IO.puts("Encoding failed: No src directory found.")
      IO.puts("Run `pled pull` first.")
      System.halt(1)
    end

    case build(opts) do
      {:ok, payload, []} ->
        write_and_report(payload, opts)

      {:ok, payload, issues} ->
        print_issues(issues)

        cond do
          Prompt.interactive?() ->
            if Prompt.confirm?("Apply these changes and continue? [y/N]: ") do
              write_and_report(payload, opts)
            else
              IO.puts("Encoding cancelled.")
              {:error, :cancelled}
            end

          true ->
            IO.puts("Cannot confirm these changes in a non-interactive session.")
            IO.puts("Fix the issues above, or run `pled encode` from a terminal to confirm them.")
            {:error, :unresolved_issues}
        end

      {:error, reason} ->
        IO.puts("Encoding failed: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Pure build step: reads the source tree and returns the Bubble payload.

  Returns `{:ok, payload, issues}` where `issues` is a list of structured
  validation issues whose resolutions are already applied to `payload`, or
  `{:error, reason}`. Performs no file writes and no prompts.
  """
  def build(opts \\ []) do
    src_dir = Keyword.get(opts, :src_dir, "src")

    opts =
      opts
      |> Keyword.put(:src_dir, src_dir)
      |> Keyword.put_new(:elements_dir, Path.join(src_dir, "elements"))
      |> Keyword.put_new(:actions_dir, Path.join(src_dir, "actions"))

    with {:ok, src_json} <- read_src_json(src_dir),
         {:ok, json_with_elements, issues} <- Element.encode_elements(src_json, opts) do
      payload =
        json_with_elements
        |> Action.encode_actions(opts)
        |> encode_html(opts)

      {:ok, payload, issues}
    end
  rescue
    e in File.Error ->
      {:error,
       "#{Exception.message(e)}. Restore the file or run `pled pull` to re-fetch the plugin."}
  end

  @doc """
  Writes the built payload to `dist/plugin.json`.
  """
  def write_dist(payload, opts \\ []) do
    dist_dir = Keyword.get(opts, :dist_dir, "dist")
    File.mkdir_p(dist_dir)
    path = Path.join(dist_dir, "plugin.json")

    case File.write(path, Jason.encode!(payload, pretty: true)) do
      :ok -> :ok
      {:error, reason} -> {:error, "Failed to write #{path}: #{:file.format_error(reason)}"}
    end
  end

  def encode_html(json, opts \\ []) do
    verbose? = Keyword.get(opts, :verbose, false)
    UI.info("reading shared html...", verbose?)
    src_dir = Keyword.get(opts, :src_dir)
    html_path = Path.join(src_dir, "shared.html")

    if File.exists?(html_path) do
      snippet = File.read!(html_path)
      Map.merge(json, %{"html_header" => %{"snippet" => snippet}})
    else
      json
    end
  end

  defp write_and_report(payload, opts) do
    verbose? = Keyword.get(opts, :verbose, false)
    UI.info("generated output json, writing it to dist/plugin.json", verbose?)

    case write_dist(payload, opts) do
      :ok ->
        IO.puts("dist/plugin.json generated")
        :ok

      {:error, reason} ->
        IO.puts("Encoding failed: #{reason}")
        {:error, reason}
    end
  end

  defp read_src_json(src_dir) do
    path = Path.join(src_dir, "plugin.json")

    with {:ok, content} <- File.read(path),
         {:ok, json} <- Jason.decode(content) do
      {:ok, json}
    else
      {:error, %Jason.DecodeError{} = error} ->
        {:error, "#{path} is not valid JSON: #{Exception.message(error)}"}

      {:error, reason} ->
        {:error,
         "Failed to read #{path}: #{:file.format_error(reason)}. " <>
           "Run `pled pull` to fetch the plugin."}
    end
  end

  defp print_issues(issues) do
    IO.puts("")
    IO.puts("The following changes need confirmation:")
    Enum.each(issues, &print_issue/1)
    IO.puts("")
  end

  defp print_issue(%{type: :field_caption_change} = issue) do
    IO.puts(
      "  • [#{issue.element}] field #{issue.field} caption: " <>
        "#{inspect(issue.from)} → #{inspect(issue.to)}"
    )
  end

  defp print_issue(%{type: :action_mismatch} = issue) do
    IO.puts("  • [#{issue.element}] element actions out of sync with JS files (auto-fix):")

    Enum.each(issue.orphaned_files, fn key ->
      IO.puts("      - create action #{key} from its JS file")
    end)

    Enum.each(issue.orphaned_json, fn key ->
      IO.puts("      - remove action #{key} (no matching JS file)")
    end)
  end
end
