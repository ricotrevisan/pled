defmodule Pled.Commands.Upload do
  @moduledoc """
  Command for uploading files to Bubble.io CDN.
  """
  alias Pled.UI

  def help do
    IO.puts("""
    Usage:
      pled upload <file_path> [options]

    Description:
      Uploads a file to the Bubble.io CDN and adds the resulting CDN URL
      as an asset entry in src/plugin.json.

    Arguments:
      <file_path>      Path to the file to upload

    Options:
      --verbose, -v    Show detailed output
      --help, -h       Show this help message

    Examples:
      pled upload lib/dist.js        Upload a bundled JS file
      pled upload assets/icon.png    Upload an image asset
    """)

    :ok
  end

  def run(file_path, opts \\ []) do
    verbose? = Keyword.get(opts, :verbose, false)
    IO.puts("uploading")

    UI.info("Uploading file: #{file_path}", verbose?)

    plugin_file = "src/plugin.json"

    case File.exists?(plugin_file) do
      false ->
        IO.puts("Upload failed: src/plugin.json not found")
        {:error, "src/plugin.json not found"}

      true ->
        case File.exists?(file_path) do
          false ->
            IO.puts("Upload failed: File '#{file_path}' does not exist")
            {:error, :file_not_found}

          true ->
            case Pled.BubbleApi.upload_file(file_path) do
              {:ok, cdn_url} ->
                UI.info("File uploaded successfully!", verbose?)
                UI.info("CDN URL: #{cdn_url}", verbose?)

                case add_asset_to_plugin(file_path, cdn_url) do
                  :ok ->
                    UI.info("Asset added to plugin.json", verbose?)
                    IO.puts("Upload completed")
                    :ok

                  {:error, reason} ->
                    UI.warn("Warning: Failed to update plugin.json: #{reason}", verbose?)
                    IO.puts("Upload completed")
                    :ok
                end

              {:error, reason} ->
                IO.puts("Upload failed: #{reason}")
                {:error, reason}
            end
        end
    end
  end

  defp add_asset_to_plugin(file_path, cdn_url) do
    plugin_file = "src/plugin.json"

    with {:ok, content} <- File.read(plugin_file),
         {:ok, plugin_data} <- Jason.decode(content) do
      filename = Path.basename(file_path)
      asset_key = generate_asset_key(plugin_data)

      asset_entry = %{
        "name" => filename,
        "url" => cdn_url
      }

      updated_assets = Map.put(plugin_data["assets"] || %{}, asset_key, asset_entry)
      updated_plugin = Map.put(plugin_data, "assets", updated_assets)

      case Jason.encode(updated_plugin, pretty: true) do
        {:ok, json_content} ->
          File.write(plugin_file, json_content)

        {:error, reason} ->
          {:error, "Failed to encode JSON: #{reason}"}
      end
    else
      {:error, reason} -> {:error, "Failed to process plugin.json: #{reason}"}
    end
  end

  defp generate_asset_key(plugin_data) do
    Pled.AssetKey.generate_from_plugin_data(plugin_data)
  end
end
