defmodule Pled.Commands.Encoder.Element do
  @moduledoc """
  Encodes element directories from `src/elements/` into the Bubble payload.

  Pure with respect to the filesystem (reads only) and never prompts:
  confirmable conditions (field caption changes, action mismatches) are
  returned as structured validation issues with their resolutions already
  applied to the returned json.
  """

  alias Pled.UI

  def encode_elements(%{} = src_json, opts) do
    verbose? = Keyword.get(opts, :verbose, false)
    UI.info("checking if plugin has elements...", verbose?)

    elements_dir = Keyword.get(opts, :elements_dir)

    if File.exists?(elements_dir) do
      UI.info("encoding elements...", verbose?)

      found_elements =
        elements_dir
        |> File.ls!()
        |> Enum.reject(&String.starts_with?(&1, "."))

      UI.info(
        "found #{Enum.count(found_elements)} element#{if Enum.count(found_elements) == 1, do: "", else: "s"}: #{Enum.join(found_elements, ", ")}",
        verbose?
      )

      result =
        Enum.reduce_while(
          found_elements,
          {:ok, %{}, []},
          fn element_dir, {:ok, acc, issues} ->
            case encode_element(Path.join(elements_dir, element_dir), opts) do
              {:ok, {key, json}, new_issues} ->
                {:cont, {:ok, Map.put(acc, key, json), issues ++ new_issues}}

              {:error, reason} ->
                {:halt, {:error, reason}}
            end
          end
        )

      case result do
        {:ok, elements, issues} ->
          {:ok, Map.merge(src_json, %{"plugin_elements" => elements}), issues}

        {:error, reason} ->
          {:error, reason}
      end
    else
      UI.info("no elements found", verbose?)
      {:ok, src_json, []}
    end
  end

  def encode_element(element_dir, opts \\ []) do
    verbose? = Keyword.get(opts, :verbose, false)
    UI.info("encoding element #{element_dir}", verbose?)

    key = element_key(element_dir)

    json =
      element_dir
      |> Path.join("#{key}.json")
      |> File.read!()
      |> Jason.decode!()

    json =
      json
      |> Map.merge(generate_code_block(element_dir))
      |> generate_html_headers(element_dir)

    with {:ok, json, field_issues} <- update_element_fields(json, element_dir, opts),
         {:ok, json, action_issues} <- update_element_actions_js(json, element_dir, opts) do
      {:ok, {key, json}, field_issues ++ action_issues}
    end
  end

  defp element_key(element_dir) do
    element_dir |> String.split("-") |> List.last()
  end

  def generate_html_headers(json, element_dir) do
    html_path = Path.join(element_dir, "headers.html")

    if File.exists?(html_path) do
      snippet = File.read!(html_path)
      Map.merge(json, %{"headers" => %{"snippet" => snippet}})
    else
      json
    end
  end

  def generate_code_block(element_dir) do
    generated_functions =
      [:initialize, :preview, :reset, :update]
      |> Enum.map(fn type ->
        generate_js_file(type, element_dir)
      end)
      |> Enum.reduce(%{}, fn map, acc ->
        Map.merge(acc, map)
      end)

    %{"code" => generated_functions}
  end

  def generate_js_file(:initialize, element_dir) do
    content = File.read!(element_dir |> Path.join("initialize.js"))

    %{
      "initialize" => %{
        "fn" => "function(instance, context) {\n" <> content <> "\n}"
      }
    }
  end

  def generate_js_file(:update, element_dir) do
    content = File.read!(element_dir |> Path.join("update.js"))

    %{
      "update" => %{
        "fn" => "function(instance, properties, context) {\n" <> content <> "\n}"
      }
    }
  end

  def generate_js_file(:preview, element_dir) do
    content = File.read!(element_dir |> Path.join("preview.js"))

    %{
      "preview" => %{
        "fn" => "function(instance, properties) {\n" <> content <> "\n}"
      }
    }
  end

  def generate_js_file(:reset, element_dir) do
    content = File.read!(element_dir |> Path.join("reset.js"))

    %{
      "reset" => %{
        "fn" => "function(instance, context) {\n" <> content <> "\n}"
      }
    }
  end

  def update_element_actions_js(json, element_dir, opts \\ []) do
    actions_dir = Path.join(element_dir, "actions")
    verbose? = Keyword.get(opts, :verbose, false)

    if File.exists?(actions_dir) and Map.has_key?(json, "actions") do
      UI.info("updating element actions from #{actions_dir}", verbose?)

      existing_actions = json["actions"]

      js_files =
        actions_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".js"))

      case validate_actions_sync(existing_actions, js_files, actions_dir) do
        {:ok, _} ->
          updated_actions = apply_js_files(existing_actions, js_files, actions_dir)
          {:ok, Map.put(json, "actions", updated_actions), []}

        {:error, :mismatch, details} ->
          fixed_actions = auto_fix_action_mismatches(existing_actions, details, js_files)
          updated_actions = apply_js_files(fixed_actions, js_files, actions_dir)

          issue = %{
            type: :action_mismatch,
            element: element_key(element_dir),
            orphaned_files: details.orphaned_files,
            orphaned_json: details.orphaned_json
          }

          {:ok, Map.put(json, "actions", updated_actions), [issue]}

        {:error, :validation_failed, errors} ->
          message =
            "Element action validation failed in #{actions_dir}:\n" <>
              Enum.map_join(errors, "\n", fn error -> "  • #{error}" end)

          {:error, message}
      end
    else
      if File.exists?(actions_dir) and not Map.has_key?(json, "actions") do
        IO.puts("Warning: Actions directory exists but no actions found in JSON")
      end

      {:ok, json, []}
    end
  end

  defp apply_js_files(actions, js_files, actions_dir) do
    Enum.reduce(js_files, actions, fn js_file, acc ->
      update_action_with_js_file(js_file, actions_dir, acc)
    end)
  end

  # New validation function
  defp validate_actions_sync(json_actions, js_files, actions_dir) do
    # Extract keys from JS files
    file_keys =
      js_files
      |> Enum.map(&extract_key_from_filename/1)
      |> Enum.reject(&is_nil/1)

    json_keys = Map.keys(json_actions)

    # Check for critical validation errors
    validation_errors = []

    # Check for malformed filenames
    malformed_files =
      js_files
      |> Enum.filter(fn file ->
        is_nil(extract_key_from_filename(file))
      end)

    validation_errors =
      if length(malformed_files) > 0 do
        ["Malformed filenames: #{Enum.join(malformed_files, ", ")}" | validation_errors]
      else
        validation_errors
      end

    # Check for empty files
    empty_files =
      js_files
      |> Enum.filter(fn file ->
        js_path = Path.join(actions_dir, file)

        case File.read(js_path) do
          {:ok, content} -> String.trim(content) == ""
          {:error, _} -> true
        end
      end)

    validation_errors =
      if length(empty_files) > 0 do
        ["Empty or unreadable files: #{Enum.join(empty_files, ", ")}" | validation_errors]
      else
        validation_errors
      end

    # Check for duplicate keys
    duplicate_keys =
      file_keys
      |> Enum.frequencies()
      |> Enum.filter(fn {_key, count} -> count > 1 end)
      |> Enum.map(fn {key, count} -> "#{key} (#{count} files)" end)

    validation_errors =
      if length(duplicate_keys) > 0 do
        ["Duplicate action keys: #{Enum.join(duplicate_keys, ", ")}" | validation_errors]
      else
        validation_errors
      end

    # If critical errors found, stop immediately
    if length(validation_errors) > 0 do
      {:error, :validation_failed, validation_errors}
    else
      # Check for sync mismatches
      orphaned_files = file_keys -- json_keys
      orphaned_json = json_keys -- file_keys

      mismatch_details = %{
        orphaned_files: orphaned_files,
        orphaned_json: orphaned_json,
        json_count: length(json_keys),
        file_count: length(file_keys),
        valid_matches: length(json_keys -- orphaned_json)
      }

      if length(orphaned_files) > 0 or length(orphaned_json) > 0 do
        {:error, :mismatch, mismatch_details}
      else
        {:ok, mismatch_details}
      end
    end
  end

  defp extract_key_from_filename(js_file) when is_binary(js_file) do
    js_file
    |> String.replace_suffix(".js", "")
    |> String.split("-")
    |> List.last()
  end

  defp extract_key_from_filename(_), do: nil

  defp update_action_with_js_file(js_file, actions_dir, actions) do
    key = extract_key_from_filename(js_file)

    if is_nil(key) do
      IO.puts("Skipping malformed filename: #{js_file}")
      actions
    else
      js_path = Path.join(actions_dir, js_file)

      case File.read(js_path) do
        {:ok, js_content} ->
          js_content =
            if String.trim(js_content) == "" do
              IO.puts("Warning: Empty content in #{js_file}, using placeholder")
              "// Empty action file"
            else
              js_content
            end

          if Map.has_key?(actions, key) do
            updated_action =
              actions[key]
              |> Map.put("code", %{
                "fn" => "function(instance, properties, context) {\n" <> js_content <> "\n}"
              })

            Map.put(actions, key, updated_action)
          else
            IO.puts(
              "Warning: Action with key '#{key}' not found in element JSON, skipping #{js_file}"
            )

            actions
          end

        {:error, reason} ->
          IO.puts("Error reading #{js_file}: #{reason}")
          actions
      end
    end
  end

  # Resolves orphaned JSON actions and JS files; the caller reports the
  # applied resolution as an :action_mismatch issue.
  defp auto_fix_action_mismatches(existing_actions, details, js_files) do
    actions_after_deletion = Map.drop(existing_actions, details.orphaned_json)

    Enum.reduce(details.orphaned_files, actions_after_deletion, fn key, acc ->
      js_file =
        Enum.find(js_files, fn file ->
          extract_key_from_filename(file) == key
        end)

      if js_file do
        # Extract action name from filename (everything before the last dash)
        action_name =
          js_file
          |> String.replace_suffix(".js", "")
          |> String.split("-")
          |> Enum.drop(-1)
          |> Enum.join("-")
          |> String.replace("-", " ")
          |> String.trim()

        action_name =
          if action_name == "",
            do: String.replace_suffix(js_file, ".js", ""),
            else: action_name

        new_action = %{
          "caption" => action_name,
          "code" => %{
            "fn" =>
              "function(instance, properties, context) {\n// Placeholder - will be updated from #{js_file}\n}"
          }
        }

        Map.put(acc, key, new_action)
      else
        acc
      end
    end)
  end

  # Field reordering functionality
  def update_element_fields(json, element_dir, opts \\ []) do
    fields_path = Path.join(element_dir, "fields.txt")
    verbose? = Keyword.get(opts, :verbose, false)

    if File.exists?(fields_path) do
      UI.info("updating element fields from #{fields_path}", verbose?)

      case File.read(fields_path) do
        {:ok, fields_content} ->
          # Check if fields exist in JSON, if not, restore from original plugin data
          existing_fields = Map.get(json, "fields", %{})

          if map_size(existing_fields) == 0 do
            case restore_original_fields(element_dir, verbose?) do
              {:ok, original_fields} ->
                process_fields_update(json, fields_content, original_fields, element_dir)

              :skip ->
                {:ok, json, []}
            end
          else
            process_fields_update(json, fields_content, existing_fields, element_dir)
          end

        {:error, reason} ->
          {:error, "Failed to read fields.txt: #{reason}"}
      end
    else
      {:ok, json, []}
    end
  end

  defp restore_original_fields(element_dir, verbose?) do
    # Read the preserved original plugin.json to get the full field definitions
    # element_dir is like "src/elements/tiptap-AAC", so we need to go up to "src" level
    plugin_path =
      element_dir
      |> Path.dirname()
      |> Path.dirname()
      |> Path.join("plugin.json")

    element_key = element_key(element_dir)

    with true <- File.exists?(plugin_path),
         {:ok, plugin_content} <- File.read(plugin_path),
         {:ok, plugin_data} <- Jason.decode(plugin_content),
         %{} = original_fields <-
           get_in(plugin_data, ["plugin_elements", element_key, "fields"]) do
      UI.info("Restoring fields from original plugin data for element #{element_key}", verbose?)
      {:ok, original_fields}
    else
      _ ->
        IO.puts(
          "Warning: Could not restore original fields for element #{element_key} from #{plugin_path}, skipping field restoration"
        )

        :skip
    end
  end

  defp process_fields_update(json, fields_content, original_fields, element_dir) do
    with {:ok, parsed_fields} <- parse_fields_txt(fields_content),
         {:ok, changes} <- validate_fields_changes(parsed_fields, original_fields) do
      issues =
        changes
        |> Enum.filter(& &1.caption_changed)
        |> Enum.map(fn change ->
          %{
            type: :field_caption_change,
            element: element_key(element_dir),
            field: change.key,
            from: change.original_caption,
            to: change.caption
          }
        end)

      {:ok, apply_fields_update(json, parsed_fields, original_fields), issues}
    end
  end

  defp parse_fields_txt(content) do
    lines =
      content
      |> String.split("\n")
      |> Enum.reject(&(String.trim(&1) == ""))

    parsed_fields =
      lines
      |> Enum.with_index()
      |> Enum.map(fn {line, index} ->
        case Regex.run(~r/^(.+) \(([^)]+)\)$/, line) do
          [_full, caption, key] ->
            {:ok, %{caption: caption, key: key, rank: index}}

          _ ->
            {:error, "Malformed line: #{line}"}
        end
      end)

    # Check for parsing errors
    errors = Enum.filter(parsed_fields, &match?({:error, _}, &1))

    if length(errors) > 0 do
      error_messages = Enum.map(errors, fn {:error, msg} -> msg end)
      {:error, "Field parsing failed:\n" <> Enum.join(error_messages, "\n")}
    else
      valid_fields = Enum.map(parsed_fields, fn {:ok, field} -> field end)
      {:ok, valid_fields}
    end
  end

  defp validate_fields_changes(parsed_fields, original_fields) do
    original_keys = Map.keys(original_fields)
    parsed_keys = Enum.map(parsed_fields, & &1.key)

    # Check for duplicate keys
    duplicate_keys =
      parsed_keys
      |> Enum.frequencies()
      |> Enum.filter(fn {_key, count} -> count > 1 end)
      |> Enum.map(fn {key, count} -> "#{key} (appears #{count} times)" end)

    if length(duplicate_keys) > 0 do
      {:error, "Duplicate keys found:\n" <> Enum.join(duplicate_keys, "\n")}
    else
      # Check for missing or extra keys
      missing_keys = original_keys -- parsed_keys
      extra_keys = parsed_keys -- original_keys

      cond do
        length(missing_keys) > 0 ->
          {:error, "Missing keys from original fields: #{Enum.join(missing_keys, ", ")}"}

        length(extra_keys) > 0 ->
          {:error, "Extra keys not in original fields: #{Enum.join(extra_keys, ", ")}"}

        true ->
          changes = detect_changes(parsed_fields, original_fields)
          {:ok, changes}
      end
    end
  end

  defp detect_changes(parsed_fields, original_fields) do
    Enum.map(parsed_fields, fn parsed_field ->
      original_key = parsed_field.key
      original_field = original_fields[original_key]

      %{
        key: parsed_field.key,
        caption: parsed_field.caption,
        rank: parsed_field.rank,
        original_caption: original_field["caption"],
        original_key: original_key,
        caption_changed: parsed_field.caption != original_field["caption"],
        # Key changes not implemented in this version
        key_changed: false
      }
    end)
  end

  defp apply_fields_update(json, parsed_fields, original_fields) do
    # Reassign the original rank values (sorted) by fields.txt line order so an
    # untouched tree round-trips to the exact remote ranks.
    ranks =
      original_fields
      |> Enum.map(fn {_key, field} -> field["rank"] end)
      |> Enum.sort()

    updated_fields =
      parsed_fields
      |> Enum.reduce(%{}, fn parsed_field, acc ->
        original_field_data = original_fields[parsed_field.key]
        rank = Enum.at(ranks, parsed_field.rank) || parsed_field.rank

        updated_field_data =
          original_field_data
          |> Map.put("caption", parsed_field.caption)
          |> Map.put("rank", rank)

        Map.put(acc, parsed_field.key, updated_field_data)
      end)

    Map.put(json, "fields", updated_fields)
  end
end
