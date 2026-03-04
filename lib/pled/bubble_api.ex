defmodule Pled.BubbleApi do
  @moduledoc """
  API client for interacting with Bubble.io plugin endpoints.
  """

  @base_url "https://bubble.io/appeditor"

  @doc """
  Fetches plugin data from Bubble.io.

  Reads plugin ID from `.plugin_id` file (falls back to PLUGIN_ID env var).
  Requires COOKIE environment variable for authentication.

  Returns `{:ok, plugin_data}` on success or `{:error, reason}` on failure.
  """
  def fetch_plugin do
    with {:ok, plugin_id} <- Pled.PluginId.load(),
         {:ok, cookie} <- get_env_var("COOKIE") do
      url = "#{@base_url}/get_plugin?id=#{plugin_id}"

      headers = [
        {"cookie", cookie},
        {"user-agent", "Pled/0.1.0"}
      ]

      case Req.get(url, headers: headers) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, body}

        {:ok, %{status: status, body: body}} ->
          {:error, "HTTP #{status}: #{inspect(body)}"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  def save_plugin do
    IO.puts("Uploading plugin...")

    with {:ok, plugin_id} <- Pled.PluginId.load(),
         {:ok, cookie} <- get_env_var("COOKIE") do
      url = "https://bubble.io/appeditor/save_plugin"

      headers = [
        {"cookie", cookie},
        {"content-type", "application/json"}
      ]

      content = File.read!("dist/plugin.json")

      body = %{"id" => plugin_id, "raw" => Jason.decode!(content)}

      case Req.post(url, headers: headers, body: Jason.encode!(body)) do
        {:ok, %{status: 200}} ->
          IO.puts("Plugin uploaded successfully")
          :ok

        {:ok, response} ->
          IO.warn("Plugin uploaded failed")
          IO.warn("Response: #{inspect(response)}")
          {:error, :not_saved}

        {:error, reason} ->
          IO.warn("Plugin upload failed")
          IO.warn("Reason: #{inspect(reason)}")

          {:error, reason}
      end
    end
  end

  @doc """
  Uploads a file to Bubble.io.

  ## Parameters
  - `file_path`: Path to the file to upload
  - `file_type`: MIME type of the file (optional, defaults to "text/javascript")

  Requires environment variable:
  - COOKIE: Authentication cookie for Bubble.io

  Returns `{:ok, cdn_url}` on success or `{:error, reason}` on failure.

  The successful response contains a CDN URL string where the uploaded file can be accessed,
  e.g., "//meta-q.cdn.bubble.io/f1753595499566x160973835258829250/dist.js"
  """
  def upload_file(file_path, file_type \\ "text/javascript") do
    with {:ok, cookie} <- get_env_var("COOKIE"),
         {:ok, file_contents} <- File.read(file_path) do
      url = "https://bubble.io/fileupload"

      headers = [
        {"cookie", cookie},
        {"content-type", "application/json; charset=utf-8"}
      ]

      filename = Path.basename(file_path)
      encoded_contents = Base.encode64(file_contents)

      body = %{
        "app_version" => "live",
        "type" => file_type,
        "appname" => "meta",
        "contents" => encoded_contents,
        "name" => filename
      }

      case Req.post(url, headers: headers, body: Jason.encode!(body)) do
        {:ok, %{status: 200, body: response_body}} ->
          {:ok, response_body}

        {:ok, %{status: status, body: body}} ->
          {:error, "HTTP #{status}: #{inspect(body)}"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_env_var(name) do
    case System.get_env(name) do
      nil -> {:error, "Environment variable #{name} is not set"}
      value -> {:ok, value}
    end
  end
end
