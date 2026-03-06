defmodule Pled.Commands.Encoder do
  @moduledoc """
  Module that turns the local files into Bubble-accepted json
  """
  alias Pled.Commands.Encoder.Element
  alias Pled.Commands.Encoder.Action
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
    verbose? = Keyword.get(opts, :verbose, false)
    IO.puts("encoding")

    if not File.exists?("src/") do
      IO.puts("Encoding failed: No src directory found.")
      IO.puts("Run `pled pull` first.")
      System.halt(1)
    end

    dist_dir = "dist"
    File.mkdir_p(dist_dir)

    src_dir = "src"

    src_json =
      src_dir
      |> Path.join("plugin.json")
      |> File.read!()
      |> Jason.decode!()

    opts = [
      src_dir: src_dir,
      dist_dir: dist_dir,
      elements_dir: Path.join(src_dir, "elements"),
      actions_dir: Path.join(src_dir, "actions"),
      verbose: verbose?
    ]

    case Element.encode_elements(src_json, opts) do
      {:ok, json_with_elements} ->
        output_json =
          json_with_elements
          |> Action.encode_actions(opts)
          |> encode_html(opts)

        UI.info("generated output json, writing it to dist/plugin.json", verbose?)

        dist_dir
        |> Path.join("plugin.json")
        |> File.write(output_json |> Jason.encode!(pretty: true))

        IO.puts("dist/plugin.json generated")
        :ok

      {:error, reason} ->
        IO.puts("Encoding failed: #{reason}")
        {:error, reason}
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
end
