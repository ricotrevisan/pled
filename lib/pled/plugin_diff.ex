defmodule Pled.PluginDiff do
  @moduledoc """
  Computes structured diffs between two canonical plugin representations.

  The diff output is path-addressable so future commands (like
  `pled check_remote`) can surface precise changes instead of coarse tuples.
  """

  alias Pled.PluginModel

  defmodule Change do
    @moduledoc false
    defstruct type: nil, path: [], before: nil, after: nil, meta: %{}
  end

  @enforce_keys [:changes, :summary, :left_hash, :right_hash]
  defstruct changes: [], summary: %{}, left_hash: nil, right_hash: nil

  @type t :: %__MODULE__{
          changes: [Change.t()],
          summary: %{optional(atom()) => non_neg_integer()},
          left_hash: String.t() | nil,
          right_hash: String.t() | nil
        }

  @doc """
  Produces a structured diff between two plugin payloads or models.
  """
  @spec diff(PluginModel.t() | map(), PluginModel.t() | map()) :: t()
  def diff(left, right) do
    left_model = ensure_model(left)
    right_model = ensure_model(right)

    left_map = PluginModel.to_serializable_map(left_model)
    right_map = PluginModel.to_serializable_map(right_model)

    changes = []
    changes = diff_metadata(changes, left_map["metadata"], right_map["metadata"])
    changes = diff_html_header(changes, left_map["html_header"], right_map["html_header"])
    changes = diff_entities(changes, left_map["elements"], right_map["elements"], :element)
    changes = diff_entities(changes, left_map["actions"], right_map["actions"], :action)

    changes = Enum.reverse(changes)

    %__MODULE__{
      changes: changes,
      summary: summarize(changes),
      left_hash: PluginModel.fingerprint(left_model),
      right_hash: PluginModel.fingerprint(right_model)
    }
  end

  @doc """
  True when the diff detected at least one change.
  """
  @spec changed?(t()) :: boolean()
  def changed?(%__MODULE__{changes: []}), do: false
  def changed?(%__MODULE__{}), do: true

  # -- Diff helpers ----------------------------------------------------------

  defp ensure_model(%PluginModel{} = model), do: model

  defp ensure_model(%{} = payload) do
    PluginModel.from_remote!(payload)
  end

  defp diff_metadata(changes, left, right) do
    diff_map(
      changes,
      left || %{},
      right || %{},
      ["metadata"],
      :metadata_field_changed,
      %{}
    )
  end

  defp diff_html_header(changes, left, right) do
    diff_value(changes, left, right, ["html_header"], :html_header_changed, %{})
  end

  defp diff_entities(changes, left_list, right_list, entity_type) do
    left_map = index_by_key(left_list)
    right_map = index_by_key(right_list)

    left_keys = Map.keys(left_map)
    right_keys = Map.keys(right_map)

    removed = left_keys -- right_keys
    added = right_keys -- left_keys
    shared = left_keys -- removed

    path_fn = entity_path_fun(entity_type)

    changes =
      Enum.reduce(Enum.sort(removed), changes, fn key, acc ->
        [
          change(
            change_atom(entity_type, :removed),
            path_fn.(key),
            left_map[key],
            nil,
            %{entity: entity_type, key: key}
          )
          | acc
        ]
      end)

    changes =
      Enum.reduce(Enum.sort(added), changes, fn key, acc ->
        [
          change(
            change_atom(entity_type, :added),
            path_fn.(key),
            nil,
            right_map[key],
            %{entity: entity_type, key: key}
          )
          | acc
        ]
      end)

    Enum.reduce(Enum.sort(shared), changes, fn key, acc ->
      diff_map(
        acc,
        left_map[key],
        right_map[key],
        path_fn.(key),
        change_atom(entity_type, :field_changed),
        %{entity: entity_type, key: key}
      )
    end)
  end

  defp diff_map(changes, nil, nil, _path, _type, _meta), do: changes

  defp diff_map(changes, left, right, path, type, meta) do
    left = left || %{}
    right = right || %{}

    keys =
      (Map.keys(left) ++ Map.keys(right))
      |> Enum.uniq()
      |> Enum.sort()

    Enum.reduce(keys, changes, fn key, acc ->
      diff_value(acc, Map.get(left, key), Map.get(right, key), path ++ [key], type, meta)
    end)
  end

  defp diff_value(changes, value, value, _path, _type, _meta), do: changes

  defp diff_value(
         changes,
         %{"__type" => "code_block"} = left,
         %{"__type" => "code_block"} = right,
         path,
         type,
         meta
       ) do
    cond do
      left["fingerprint"] == right["fingerprint"] ->
        changes

      left["raw"] != right["raw"] ->
        diff_value(changes, left["raw"], right["raw"], path ++ ["raw"], type, meta)

      true ->
        [
          change(
            type,
            path ++ ["fingerprint"],
            left["fingerprint"],
            right["fingerprint"],
            meta
          )
          | changes
        ]
    end
  end

  defp diff_value(changes, %{} = left, %{} = right, path, type, meta) do
    diff_map(changes, left, right, path, type, meta)
  end

  defp diff_value(changes, left, right, path, type, meta) do
    [change(type, path, left, right, meta) | changes]
  end

  defp summarize(changes) do
    Enum.reduce(changes, %{}, fn %Change{type: type}, acc ->
      Map.update(acc, type, 1, &(&1 + 1))
    end)
  end

  defp change_atom(:element, suffix), do: String.to_atom("element_" <> suffix_to_string(suffix))
  defp change_atom(:action, suffix), do: String.to_atom("action_" <> suffix_to_string(suffix))

  defp suffix_to_string(:added), do: "added"
  defp suffix_to_string(:removed), do: "removed"
  defp suffix_to_string(:field_changed), do: "field_changed"

  defp index_by_key(nil), do: %{}

  defp index_by_key(list) when is_list(list) do
    Enum.reduce(list, %{}, fn entry, acc ->
      case Map.get(entry, "key") do
        nil -> acc
        key -> Map.put(acc, key, entry)
      end
    end)
  end

  defp index_by_key(_), do: %{}

  defp entity_path_fun(:element), do: fn key -> ["elements", key] end
  defp entity_path_fun(:action), do: fn key -> ["actions", key] end

  defp change(type, path, before, after_value, meta) do
    %Change{type: type, path: path, before: before, after: after_value, meta: meta}
  end
end
