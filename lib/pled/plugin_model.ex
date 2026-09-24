defmodule Pled.PluginModel do
  @moduledoc """
  Canonical representation of Bubble plugin data used for deterministic
  comparisons and future structural diffing.
  """

  alias __MODULE__.{Action, Element}
  alias Pled.CodeBlock
  alias Slug

  @enforce_keys [:metadata, :elements, :actions, :html_header, :raw, :canonical]
  defstruct metadata: %{},
            elements: [],
            actions: [],
            html_header: nil,
            raw: %{},
            canonical: nil

  @type t :: %__MODULE__{
          metadata: map(),
          elements: [Element.t()],
          actions: [Action.t()],
          html_header: map() | nil,
          raw: map(),
          canonical: term()
        }

  @doc """
  Builds a canonical plugin model from remote (Bubble) JSON.
  """
  @spec from_remote(map()) :: {:ok, t()} | {:error, atom()}
  def from_remote(%{} = plugin) do
    {:ok, build_model(plugin)}
  end

  def from_remote(_), do: {:error, :invalid_plugin_payload}

  @doc """
  Convenience bang variant for trusted data (e.g., our own encoder output).
  """
  @spec from_remote!(map()) :: t()
  def from_remote!(%{} = plugin), do: build_model(plugin)

  @doc """
  Returns a stable fingerprint for the provided plugin data or model.
  """
  @spec fingerprint(t() | map()) :: String.t()
  def fingerprint(%__MODULE__{canonical: canonical}), do: hash_term(canonical)

  def fingerprint(%{} = plugin), do: plugin |> from_remote!() |> fingerprint()

  @doc """
  Compares two plugin payloads (or models) after canonicalization.
  """
  @spec equal?(t() | map(), t() | map()) :: boolean()
  def equal?(plugin_a, plugin_b) do
    fingerprint(plugin_a) == fingerprint(plugin_b)
  end

  @doc """
  Serializes the model back to the sanitized map used for hashing/diffing.
  """
  @spec to_serializable_map(t()) :: map()
  def to_serializable_map(%__MODULE__{} = model) do
    %{
      "metadata" => model.metadata,
      "elements" => Enum.map(model.elements, &Element.serializable/1),
      "actions" => Enum.map(model.actions, &Action.serializable/1),
      "html_header" => model.html_header
    }
  end

  # -- Internal ----------------------------------------------------------------

  defp build_model(%{} = plugin) do
    metadata = extract_metadata(plugin)
    elements = plugin |> Map.get("plugin_elements", %{}) |> build_elements()
    actions = plugin |> Map.get("plugin_actions", %{}) |> build_actions()
    html_header = plugin |> Map.get("html_header") |> sanitize_term()

    canonical =
      %{
        "metadata" => metadata,
        "elements" => Enum.map(elements, &Element.serializable/1),
        "actions" => Enum.map(actions, &Action.serializable/1),
        "html_header" => html_header
      }
      |> normalize_for_hash()

    %__MODULE__{
      metadata: metadata,
      elements: elements,
      actions: actions,
      html_header: html_header,
      raw: plugin,
      canonical: canonical
    }
  end

  # Bubble keeps the listing settings (name, description, categories,
  # platforms_new, ...) under "meta_data"; the flat keys cover older payloads.
  defp extract_metadata(plugin) do
    plugin
    |> Map.take(["name", "description", "author", "version", "category", "icon", "meta_data"])
    |> sanitize_term()
  end

  defp build_elements(elements_map) when elements_map in [nil, %{}], do: []

  defp build_elements(elements_map) do
    elements_map
    |> Enum.map(&Element.from_remote/1)
    |> Enum.sort_by(& &1.key)
  end

  defp build_actions(actions_map) when actions_map in [nil, %{}], do: []

  defp build_actions(actions_map) do
    actions_map
    |> Enum.map(&Action.from_remote/1)
    |> Enum.sort_by(& &1.key)
  end

  @doc false
  def normalize_for_hash(%{"__type" => "code_block"} = block) do
    block
    |> Map.take(["__type", "fingerprint"])
    |> Enum.map(fn {k, v} -> {k, normalize_for_hash(v)} end)
    |> Enum.sort_by(fn {k, _} -> k end)
  end

  def normalize_for_hash(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} -> {k, normalize_for_hash(v)} end)
    |> Enum.sort_by(fn {k, _} -> k end)
  end

  def normalize_for_hash(value) when is_list(value) do
    Enum.map(value, &normalize_for_hash/1)
  end

  def normalize_for_hash(value), do: value

  @doc false
  def hash_term(term) do
    term
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc false
  def sanitize_term(value), do: sanitize_term(value, [])

  def sanitize_term(value, path) when is_map(value) do
    value
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      case sanitize_term(v, path ++ [to_string(k)]) do
        nil -> acc
        sanitized -> Map.put(acc, k, sanitized)
      end
    end)
    |> maybe_wrap_code_block(value, path)
  end

  def sanitize_term(value, path) when is_list(value) do
    value
    |> Enum.map(&sanitize_term(&1, path))
    |> Enum.reject(&is_nil/1)
  end

  def sanitize_term(value, _path) when is_binary(value), do: value

  def sanitize_term(value, _path), do: value

  defp maybe_wrap_code_block(sanitized, original, path) do
    case original do
      %{"fn" => fn_source} when is_binary(fn_source) ->
        block = CodeBlock.from_source(fn_source, path: path ++ ["fn"])
        Map.put(sanitized, "fn", CodeBlock.to_serializable(block))

      _ ->
        sanitized
    end
  end

  # -- Nested structs -----------------------------------------------------------

  defmodule Element do
    @moduledoc false

    @enforce_keys [:key, :data]
    defstruct key: nil,
              display: nil,
              slug: nil,
              data: %{},
              hash: nil

    @type t :: %__MODULE__{
            key: String.t(),
            display: String.t() | nil,
            slug: String.t() | nil,
            data: map(),
            hash: String.t() | nil
          }

    def from_remote({key, data}) do
      sanitized = Pled.PluginModel.sanitize_term(data, ["plugin_elements", key])

      slug =
        data
        |> Map.get("display")
        |> case do
          nil -> key
          display -> display
        end
        |> Slug.slugify()

      serializable = %{
        "key" => key,
        "display" => Map.get(data, "display"),
        "data" => sanitized
      }

      %__MODULE__{
        key: key,
        display: Map.get(data, "display"),
        slug: slug,
        data: sanitized,
        hash: Pled.PluginModel.hash_term(Pled.PluginModel.normalize_for_hash(serializable))
      }
    end

    def serializable(%__MODULE__{} = element) do
      %{
        "key" => element.key,
        "display" => element.display,
        "slug" => element.slug,
        "data" => element.data
      }
    end
  end

  defmodule Action do
    @moduledoc false

    @enforce_keys [:key, :data]
    defstruct key: nil,
              display: nil,
              slug: nil,
              data: %{},
              hash: nil

    @type t :: %__MODULE__{
            key: String.t(),
            display: String.t() | nil,
            slug: String.t() | nil,
            data: map(),
            hash: String.t() | nil
          }

    def from_remote({key, data}) do
      sanitized = Pled.PluginModel.sanitize_term(data, ["plugin_actions", key])

      slug =
        data
        |> Map.get("display")
        |> case do
          nil -> key
          display -> display
        end
        |> Slug.slugify()

      serializable = %{
        "key" => key,
        "display" => Map.get(data, "display"),
        "data" => sanitized
      }

      %__MODULE__{
        key: key,
        display: Map.get(data, "display"),
        slug: slug,
        data: sanitized,
        hash: Pled.PluginModel.hash_term(Pled.PluginModel.normalize_for_hash(serializable))
      }
    end

    def serializable(%__MODULE__{} = action) do
      %{
        "key" => action.key,
        "display" => action.display,
        "slug" => action.slug,
        "data" => action.data
      }
    end
  end
end
