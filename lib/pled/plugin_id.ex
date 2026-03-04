defmodule Pled.PluginId do
  @moduledoc """
  Resolves the plugin ID from `.plugin_id` file or PLUGIN_ID env var.
  """

  @plugin_id_file ".plugin_id"

  @doc """
  Extracts a plugin ID from a Bubble URL or raw ID string.

  Accepts:
  - `https://bubble.io/plugin_editor?id=1234x5678`
  - `https://bubble.io/plugin_editor?id=1234x5678&tab=tabs-4`
  - `1234x5678`

  Returns `{:ok, id}` or `:error`.
  """
  def extract(input) do
    input = String.trim(input)

    cond do
      # URL with id param
      String.contains?(input, "bubble.io") ->
        case Regex.run(~r/[?&]id=(\d+x\d+)/, input) do
          [_, id] -> {:ok, id}
          _ -> :error
        end

      # Raw ID
      Regex.match?(~r/^\d+x\d+$/, input) ->
        {:ok, input}

      true ->
        :error
    end
  end

  @doc """
  Loads the plugin ID. Reads from `.plugin_id` file first, falls back to
  `PLUGIN_ID` env var.

  Returns `{:ok, id}` or `{:error, message}`.
  """
  def load do
    case read_file() do
      {:ok, id} -> {:ok, id}
      :error -> load_from_env()
    end
  end

  @doc """
  Saves a plugin ID to the `.plugin_id` file.
  """
  def save(id) do
    File.write(@plugin_id_file, id <> "\n")
  end

  @doc """
  Returns `{:ok, source}` where source is `:file` or `:env`, or `:error`.
  """
  def source do
    cond do
      match?({:ok, _}, read_file()) -> {:ok, :file}
      System.get_env("PLUGIN_ID") != nil -> {:ok, :env}
      true -> :error
    end
  end

  defp read_file do
    case File.read(@plugin_id_file) do
      {:ok, content} ->
        id = String.trim(content)
        if id != "", do: {:ok, id}, else: :error

      {:error, _} ->
        :error
    end
  end

  defp load_from_env do
    case System.get_env("PLUGIN_ID") do
      nil ->
        {:error,
         "Plugin ID not found. Run 'pled init <bubble-plugin-url>' or set PLUGIN_ID env var."}

      value ->
        {:ok, value}
    end
  end
end
