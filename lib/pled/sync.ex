defmodule Pled.Sync do
  @moduledoc """
  Classifies the workspace by comparing the baseline, local source, and remote plugin.

  The baseline is the existing `.src.json` snapshot, the local plugin is built
  from `src/` without writing `dist/`, and the remote plugin is fetched from
  Bubble. All three payloads are compared through `Pled.PluginModel`'s
  canonical fingerprints.
  """

  alias Pled.Commands.Encoder
  alias Pled.{BubbleApi, JsAst, PluginDiff, PluginModel}

  @type state :: :in_sync | :local_ahead | :remote_ahead | :diverged | :no_baseline
  @type error_reason :: String.t() | {:remote_unreachable, String.t()}

  @doc """
  Returns the current three-way sync state and the payloads used to determine it.
  """
  @spec status() ::
          {:ok,
           %{
             state: state(),
             base: map() | nil,
             local: map(),
             remote: map(),
             diffs: %{optional(:local | :remote) => PluginDiff.t()},
             issues: [map()]
           }}
          | {:error, error_reason()}
  def status do
    with {:ok, remote} <- fetch_remote(),
         {:ok, base} <- read_baseline(),
         {:ok, local, issues} <- build_local() do
      if is_nil(base) do
        {:ok, sync_result(:no_baseline, base, local, remote, %{}, issues)}
      else
        compare(base, local, remote, issues)
      end
    end
  end

  defp compare(base, local, remote, issues) do
    JsAst.with_cache(fn ->
      with {:ok, base_model} <- build_model(base, :baseline),
           {:ok, local_model} <- build_model(local, :local),
           {:ok, remote_model} <- build_model(remote, :remote) do
        state =
          classify(
            fingerprint(base_model),
            fingerprint(local_model),
            fingerprint(remote_model)
          )

        diffs = build_diffs(state, base_model, local_model, remote_model)
        {:ok, sync_result(state, base, local, remote, diffs, issues)}
      end
    end)
  end

  defp sync_result(state, base, local, remote, diffs, issues) do
    %{
      state: state,
      base: base,
      local: local,
      remote: remote,
      diffs: diffs,
      issues: issues
    }
  end

  @doc """
  Purely classifies three canonical fingerprints.

  A missing baseline is represented by `nil`.
  """
  @spec classify(String.t() | nil, String.t(), String.t()) :: state()
  def classify(nil, _local, _remote), do: :no_baseline

  def classify(base, local, remote) do
    cond do
      base == local and local == remote -> :in_sync
      local != base and remote == base -> :local_ahead
      local == base and remote != base -> :remote_ahead
      true -> :diverged
    end
  end

  defp build_local do
    case Encoder.build() do
      {:ok, payload, issues} when is_map(payload) and is_list(issues) ->
        {:ok, payload, issues}

      {:error, reason} ->
        {:error, "Failed to build local plugin: #{format_reason(reason)}"}

      other ->
        {:error, "Failed to build local plugin: unexpected result #{inspect(other)}"}
    end
  rescue
    error ->
      {:error,
       "Failed to build local plugin: #{Exception.message(error)}. " <>
         "Repair the local source tree or run `pled pull` to restore it."}
  end

  defp read_baseline do
    path = snapshot_file_path()

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, payload} when is_map(payload) ->
            {:ok, payload}

          {:ok, _payload} ->
            {:error,
             "Invalid baseline snapshot JSON at #{path}: expected a JSON object. " <>
               "Run `pled pull` to recreate it."}

          {:error, error} ->
            {:error,
             "Invalid baseline snapshot JSON at #{path}: #{Exception.message(error)}. " <>
               "Run `pled pull` to recreate it."}
        end

      {:error, :enoent} ->
        {:ok, nil}

      {:error, reason} ->
        {:error,
         "Failed to read baseline snapshot #{path}: #{:file.format_error(reason)}. " <>
           "Check the file permissions or run `pled pull` to recreate it."}
    end
  end

  defp fetch_remote do
    case BubbleApi.fetch_plugin() do
      {:ok, payload} when is_map(payload) ->
        {:ok, payload}

      {:ok, payload} ->
        {:error,
         {:remote_unreachable,
          "Failed to fetch remote plugin: Bubble returned an invalid payload " <>
            "(expected a JSON object, got #{inspect(payload)})."}}

      {:error, reason} ->
        {:error, {:remote_unreachable, "Failed to fetch remote plugin: #{format_reason(reason)}"}}
    end
  end

  defp build_model(nil, _source), do: {:ok, nil}

  defp build_model(payload, source) do
    case PluginModel.from_remote(payload) do
      {:ok, model} -> {:ok, model}
      {:error, reason} -> {:error, invalid_payload_message(source, format_reason(reason))}
    end
  rescue
    error ->
      {:error, invalid_payload_message(source, Exception.message(error))}
  end

  defp invalid_payload_message(:baseline, reason) do
    "Invalid baseline snapshot: #{reason}. Run `pled pull` to recreate it."
  end

  defp invalid_payload_message(:local, reason), do: "Invalid local plugin: #{reason}."
  defp invalid_payload_message(:remote, reason), do: "Invalid remote plugin: #{reason}."

  defp fingerprint(nil), do: nil
  defp fingerprint(model), do: PluginModel.fingerprint(model)

  defp build_diffs(:local_ahead, base, local, _remote) do
    %{local: PluginDiff.diff(base, local)}
  end

  defp build_diffs(:remote_ahead, base, _local, remote) do
    %{remote: PluginDiff.diff(base, remote)}
  end

  defp build_diffs(:diverged, base, local, remote) do
    %{
      local: PluginDiff.diff(base, local),
      remote: PluginDiff.diff(base, remote)
    }
  end

  defp build_diffs(_state, _base, _local, _remote), do: %{}

  defp snapshot_file_path do
    Application.get_env(:pled, :src_snapshot_file, ".src.json")
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
