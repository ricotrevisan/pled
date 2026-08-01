defmodule Pled.Commands.Decoder do
  def decode(plugin_data, base_dir \\ File.cwd!()) do
    decode_elements(plugin_data, base_dir)
    decode_actions(plugin_data, base_dir)
    decode_html_header(plugin_data, base_dir)
    prune_removed_entities(plugin_data, base_dir)
    clean_plugin_data(base_dir)
    :ok
  rescue
    # All writes below use the bang variants; any failed write aborts the
    # decode with an error naming the file instead of silently skipping.
    e in File.Error -> {:error, Exception.message(e)}
  end

  defp slug_or_key(display, key) do
    (display && Slug.slugify(display)) || Slug.slugify(key) || key
  end

  # The prune below must build names exactly like the writes do, or it deletes
  # live entities.
  defp entity_dir_name(display, key), do: "#{slug_or_key(display, key)}-#{key}"

  # Entities deleted or renamed in Bubble must not survive locally, or the next
  # push would resurrect them.
  defp prune_removed_entities(plugin_data, base_dir) do
    elements = collection(plugin_data, "plugin_elements")
    elements_dir = Path.join([base_dir, "src", "elements"])

    prune_dirs(elements_dir, entity_dir_names(elements, "display"))

    prune_dirs(
      Path.join([base_dir, "src", "actions"]),
      entity_dir_names(collection(plugin_data, "plugin_actions"), "display")
    )

    Enum.each(elements, fn {key, element_data} ->
      element_dir = Path.join(elements_dir, entity_dir_name(element_data["display"], key))

      prune_js_files(
        Path.join(element_dir, "actions"),
        element_data
        |> Map.get("actions")
        |> Kernel.||(%{})
        |> MapSet.new(fn {key, data} -> entity_dir_name(data["caption"], key) <> ".js" end)
      )
    end)
  end

  defp collection(plugin_data, key), do: Map.get(plugin_data, key) || %{}

  defp entity_dir_names(entities, name_field) do
    MapSet.new(entities, fn {key, data} -> entity_dir_name(data[name_field], key) end)
  end

  defp prune_dirs(dir, keep) do
    prune(dir, keep, &File.dir?/1)
  end

  defp prune_js_files(dir, keep) do
    prune(dir, keep, &String.ends_with?(&1, ".js"))
  end

  # Every directory here is an entity the encoder builds, so a directory the
  # remote no longer has is stale. Loose files the user keeps are left alone.
  defp prune(dir, keep, removable?) do
    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.reject(&MapSet.member?(keep, &1))
        |> Enum.map(&Path.join(dir, &1))
        |> Enum.filter(removable?)
        |> Enum.each(&File.rm_rf!/1)

      {:error, _reason} ->
        :ok
    end
  end

  def clean_plugin_data(base_dir) do
    keys_to_drop = ["html_header", "plugin_actions", "plugin_elements"]

    plugin_path = Path.join([base_dir, "src", "plugin.json"])

    updated_json =
      plugin_path
      |> File.read!()
      |> Jason.decode!()
      |> Map.drop(keys_to_drop)

    File.write!(plugin_path, Jason.encode!(updated_json, pretty: true))
  end

  def decode_html_header(plugin_data, base_dir) do
    case get_in(plugin_data, ["html_header", "snippet"]) do
      nil ->
        :ok

      snippet ->
        html_path = Path.join([base_dir, "src", "shared.html"])
        File.write!(html_path, snippet)
    end
  end

  def decode_actions(plugin_data, base_dir) do
    actions_dir = Path.join([base_dir, "src", "actions"])

    plugin_data
    |> Map.get("plugin_actions", [])
    |> Enum.map(&decode_action(&1, actions_dir))
  end

  defp decode_action({key, action_data}, actions_dir) do
    name = slug_or_key(Map.get(action_data, "display"), key)

    action_dir = Path.join(actions_dir, entity_dir_name(Map.get(action_data, "display"), key))
    File.mkdir_p!(action_dir)

    ["client", "server"]
    |> Enum.each(fn func ->
      case action_data |> get_in(["code", func, "fn"]) |> remove_bubbleisms() do
        # no such code section on the remote: absence is valid, skip the file
        nil -> :ok
        content -> action_dir |> Path.join("#{func}.js") |> File.write!(content)
      end
    end)

    clean_action_data(name, action_data, action_dir)
  end

  def clean_action_data(name, action_data, action_dir) do
    file_path = Path.join(action_dir, "#{name}.json")

    # Keep the function signature (async or not) so the encoder can rebuild
    # the exact remote wrapper; the body lives in server.js / client.js.
    code_data =
      Enum.reduce(["server", "client"], action_data["code"] || %{}, fn func, code ->
        case code do
          %{^func => %{"fn" => fn_src} = block} when is_binary(fn_src) ->
            case Pled.CodeBlock.signature(fn_src) do
              {:ok, signature} -> Map.put(code, func, Map.put(block, "fn", signature))
              :error -> Map.put(code, func, Map.delete(block, "fn"))
            end

          # a section without a body has no js file; keeping it verbatim is what
          # lets the encoder rebuild the remote payload unchanged
          _ ->
            code
        end
      end)

    updated_action_data =
      Map.put(action_data, "code", code_data)

    File.write!(file_path, Jason.encode!(updated_action_data, pretty: true))
  end

  #
  # ELEMENTS
  #
  def decode_elements(plugin_data, base_dir) do
    elements_dir = Path.join([base_dir, "src", "elements"])

    plugin_data
    |> Map.get("plugin_elements", [])
    |> Enum.map(&decode_element(&1, elements_dir))
  end

  defp decode_element({key, element_data}, elements_dir) do
    element_dir = Path.join(elements_dir, entity_dir_name(Map.get(element_data, "display"), key))

    File.mkdir_p!(element_dir)

    decode_element_html_header(element_data, element_dir)
    decode_element_functions(element_data, element_dir)
    decode_element_actions_js(element_data, element_dir)
    decode_element_fields(element_data, element_dir)

    write_cleaned_element_data("#{element_dir}/#{key}.json", element_data)
  end

  def write_cleaned_element_data(path, element_data) do
    actions =
      case Map.get(element_data, "actions", nil) do
        nil ->
          %{}

        actions ->
          Enum.reduce(actions, %{}, fn {key, value}, acc ->
            updated_value = Map.drop(value, ["code"])

            Map.merge(acc, %{key => updated_value})
          end)
      end

    cleaned_element_data =
      element_data
      |> Map.drop(["code", "headers"])
      |> Map.put("actions", actions)

    File.write!(path, Jason.encode!(cleaned_element_data, pretty: true))
  end

  def decode_element_fields(element_data, element_dir) do
    element_data
    |> Map.get("fields")
    |> case do
      nil ->
        :ok

      [] ->
        :ok

      fields ->
        simplified_fields =
          fields
          |> Enum.sort_by(fn {_key, fields} -> fields["rank"] end)
          |> Enum.map(fn {key, fields} ->
            (fields["caption"] || key) <> " (#{key})"
          end)
          |> Enum.join("\n")

        File.write!(
          Path.join([element_dir, "fields.txt"]),
          simplified_fields
        )
    end
  end

  def decode_element_functions(element_data, element_dir) do
    ["initialize", "preview", "reset", "update"]
    |> Enum.each(fn func ->
      # the encoder requires all four files, so a missing code section
      # becomes an empty placeholder
      content =
        element_data
        |> get_in(["code", func, "fn"])
        |> remove_bubbleisms()

      element_dir
      |> Path.join("#{func}.js")
      |> File.write!(content || "")
    end)
  end

  defp decode_element_actions_js(element_data, element_dir) do
    actions_dir = Path.join(element_dir, "actions")
    actions = element_data |> Map.get("actions")

    if actions do
      File.mkdir_p!(actions_dir)

      actions
      |> Enum.each(fn {key, action_data} ->
        file_name = entity_dir_name(action_data["caption"], key) <> ".js"

        # Store only the JS content for easier editing. The encoder rejects
        # empty action files, so a missing code section gets a placeholder.
        content =
          action_data
          |> get_in(["code", "fn"])
          |> remove_bubbleisms()

        content =
          if content in [nil, ""], do: "// missing action code in remote plugin", else: content

        actions_dir
        |> Path.join(file_name)
        |> File.write!(content)
      end)
    end
  end

  def decode_element_html_header(element_data, element_dir) do
    case get_in(element_data, ["headers", "snippet"]) do
      nil -> :ok
      html -> element_dir |> Path.join("headers.html") |> File.write!(html)
    end
  end

  def remove_bubbleisms(nil), do: nil

  def remove_bubbleisms(string) do
    string
    |> String.replace(~r/(async )?function\([^)]+\) \{/, "")
    |> String.replace(~r/\}\n*$/, "")
    |> String.trim()
  end
end
