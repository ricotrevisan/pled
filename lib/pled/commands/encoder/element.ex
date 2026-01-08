defmodule Pled.Commands.Encoder.Element do
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

      # Process elements and check for errors
      result =
        Enum.reduce_while(
          found_elements,
          {:ok, %{}},
          fn element_dir, {:ok, acc} ->
            case encode_element(Path.join(elements_dir, element_dir), opts) do
              {:ok, {key, json}} ->
                {:cont, {:ok, Map.put(acc, key, json)}}

              {:error, reason} ->
                {:halt, {:error, reason}}
            end
          end
        )

      case result do
        {:ok, elements} ->
          {:ok, Map.merge(src_json, %{"plugin_elements" => elements})}

        {:error, reason} ->
          IO.puts("\nElement encoding failed: #{reason}")
          {:error, reason}
      end
    else
      UI.info("no elements found", verbose?)
      {:ok, src_json}
    end
  end

  def encode_element(element_dir, opts \\ []) do
    verbose? = Keyword.get(opts, :verbose, false)
    UI.info("encoding element #{element_dir}", verbose?)

    key = element_dir |> String.split("-") |> List.last()

    json =
      element_dir
      |> Path.join("#{key}.json")
      |> File.read!()
      |> Jason.decode!()

    code_block = generate_code_block(element_dir)
    json = Map.merge(json, code_block)

    json = generate_html_headers(json, element_dir)

    json =
      case update_element_fields(json, element_dir) do
        {:error, reason} ->
          {:error, reason}

        updated_json ->
          updated_json
      end

    case json do
      {:error, reason} ->
        {:error, reason}

      updated_json ->
        case update_element_actions_js(updated_json, element_dir) do
          {:error, reason} -> {:error, reason}
          final_json -> {:ok, {key, final_json}}
        end
    end
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

  def update_element_actions_js(json, element_dir) do
    actions_dir = Path.join(element_dir, "actions")

    if File.exists?(actions_dir) and Map.has_key?(json, "actions") do
      IO.puts("updating element actions from #{actions_dir}")

      # Get existing actions from JSON
      existing_actions = json["actions"]

      # Validate and get action files
      js_files =
        actions_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".js"))

      # Perform bidirectional validation
      validation_result = validate_actions_sync(existing_actions, js_files, actions_dir)

      case validation_result do
        {:ok, _} ->
          # Proceed with encoding
          updated_actions =
            js_files
            |> Enum.reduce(existing_actions, fn js_file, acc ->
              update_action_with_js_file(js_file, actions_dir, acc)
            end)

          Map.put(json, "actions", updated_actions)

        {:error, :mismatch, details} ->
          IO.puts("\nVALIDATION FAILED: Action count mismatch detected!")
          IO.puts("JSON actions: #{map_size(existing_actions)}")
          IO.puts("JS files: #{length(js_files)}")
          IO.puts("\nDetails:")
          print_validation_details(details)

          # Ask user for confirmation with auto-fix option
          IO.puts("\nChoose an action:")
          IO.puts("  y) Continue and auto-fix mismatches")
          IO.puts("  n) Stop encoding (default)")
          IO.write("Choice (y/N): ")
          response = IO.gets("") |> String.trim() |> String.downcase()

          if response in ["y", "yes"] do
            IO.puts("Continuing with auto-fix for mismatches...")

            # Auto-fix orphaned actions
            fixed_actions = auto_fix_action_mismatches(existing_actions, details, js_files)

            updated_actions =
              js_files
              |> Enum.reduce(fixed_actions, fn js_file, acc ->
                update_action_with_js_file(js_file, actions_dir, acc)
              end)

            Map.put(json, "actions", updated_actions)
          else
            IO.puts("Encoding stopped by user. Please fix the action sync issues first.")
            {:error, "user_stopped_validation_mismatch"}
          end

        {:error, :validation_failed, errors} ->
          Enum.each(errors, fn error -> IO.puts("  • #{error}") end)
          IO.puts("\nEncoding stopped. Please fix these issues first.")
          {:error, "validation_failed"}
      end
    else
      if File.exists?(actions_dir) and not Map.has_key?(json, "actions") do
        IO.puts("Warning: Actions directory exists but no actions found in JSON")
      end

      json
    end
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

  # Enhanced key extraction with better validation
  defp extract_key_from_filename(js_file) do
    case js_file do
      file when is_binary(file) ->
        # key =
        file
        |> String.replace_suffix(".js", "")
        |> String.split("-")
        |> List.last()

      # # Validate key format (should be 3 uppercase letters)
      # if key && String.match?(key, ~r/^[A-Z]{3}$/) do
      #   key
      # else
      #   nil
      # end
      _ ->
        nil
    end
  end

  # Helper function to print validation details
  defp print_validation_details(details) do
    if length(details.orphaned_files) > 0 do
      IO.puts("  Orphaned JS files (no matching JSON action):")

      Enum.each(details.orphaned_files, fn key ->
        IO.puts("    - #{key}")
      end)
    end

    if length(details.orphaned_json) > 0 do
      IO.puts("  Orphaned JSON actions (no matching JS file):")

      Enum.each(details.orphaned_json, fn key ->
        IO.puts("    - #{key}")
      end)
    end

    IO.puts("  Summary:")
    IO.puts("    - Valid matches: #{details.valid_matches}")
    IO.puts("    - Total JSON actions: #{details.json_count}")
    IO.puts("    - Total JS files: #{details.file_count}")
  end

  # Enhanced update function with better error handling
  defp update_action_with_js_file(js_file, actions_dir, actions) do
    try do
      key = extract_key_from_filename(js_file)

      if is_nil(key) do
        IO.puts("Skipping malformed filename: #{js_file}")
        actions
      else
        # Read the JavaScript content
        js_path = Path.join(actions_dir, js_file)

        case File.read(js_path) do
          {:ok, js_content} ->
            # Validate content is not empty
            js_content =
              if String.trim(js_content) == "" do
                IO.puts("Warning: Empty content in #{js_file}, using placeholder")
                "// Empty action file"
              else
                js_content
              end

            # Update the action's JavaScript code if the action exists
            if Map.has_key?(actions, key) do
              updated_action =
                actions[key]
                |> Map.put("code", %{
                  "fn" => "function(instance, properties, context) {\n" <> js_content <> "\n}"
                })

              # IO.puts("✅ Updated action #{key} from #{js_file}")
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
    rescue
      e ->
        IO.puts("Error processing #{js_file}: #{inspect(e)}")
        IO.puts("Skipping this action...")
        actions
    end
  end

  # Auto-fix function to handle orphaned JSON actions and JS files
  defp auto_fix_action_mismatches(existing_actions, details, js_files) do
    IO.puts("Auto-fixing action mismatches...")

    # Remove orphaned JSON actions (actions without matching JS files)
    actions_after_deletion =
      if length(details.orphaned_json) > 0 do
        Enum.each(details.orphaned_json, fn key ->
          IO.puts("    - Removing action: #{key}")
        end)

        Map.drop(existing_actions, details.orphaned_json)
      else
        existing_actions
      end

    # Add missing JSON actions for orphaned JS files
    actions_after_addition =
      if length(details.orphaned_files) > 0 do
        Enum.reduce(details.orphaned_files, actions_after_deletion, fn key, acc ->
          # Find the corresponding JS file to extract the name
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
              # Remove the key part
              |> Enum.drop(-1)
              |> Enum.join("-")
              # Replace dashes with spaces for caption
              |> String.replace("-", " ")
              |> String.trim()

            # Use filename as fallback if name extraction fails
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

            IO.puts("    - Creating action: #{key} (#{action_name})")
            Map.put(acc, key, new_action)
          else
            IO.puts("    - Warning: Could not find JS file for key #{key}")
            acc
          end
        end)
      else
        actions_after_deletion
      end

    actions_after_addition
  end

  # Field reordering functionality
  def update_element_fields(json, element_dir) do
    fields_path = Path.join(element_dir, "fields.txt")

    if File.exists?(fields_path) do
      IO.puts("updating element fields from #{fields_path}")

      case File.read(fields_path) do
        {:ok, fields_content} ->
          # Check if fields exist in JSON, if not, restore from original plugin data
          existing_fields = Map.get(json, "fields", %{})

          if map_size(existing_fields) == 0 do
            # Fields were cleaned out, need to restore from original plugin data
            restore_fields_from_original(json, fields_content, element_dir)
          else
            process_fields_update(json, fields_content, existing_fields)
          end

        {:error, reason} ->
          {:error, "Failed to read fields.txt: #{reason}"}
      end
    else
      json
    end
  end

  defp restore_fields_from_original(json, fields_content, element_dir) do
    # Read the preserved original plugin.json to get the full field definitions
    # element_dir is like "src/elements/tiptap-AAC", so we need to go up to "src" level
    plugin_path =
      element_dir
      |> Path.dirname()
      |> Path.dirname()
      |> Path.join("plugin.json")

    if File.exists?(plugin_path) do
      # Get the element key from the directory name
      element_key = element_dir |> String.split("-") |> List.last()

      case File.read(plugin_path) do
        {:ok, plugin_content} ->
          case Jason.decode(plugin_content) do
            {:ok, plugin_data} ->
              original_fields = get_in(plugin_data, ["plugin_elements", element_key, "fields"])

              if original_fields do
                IO.puts("Restoring fields from original plugin data for element #{element_key}")
                process_fields_update(json, fields_content, original_fields)
              else
                IO.puts(
                  "Warning: Could not find original fields data for element #{element_key}, skipping field restoration"
                )

                json
              end

            {:error, decode_error} ->
              IO.puts(
                "Warning: Could not parse original plugin.json (#{inspect(decode_error)}), skipping field restoration"
              )

              json
          end

        {:error, read_error} ->
          IO.puts(
            "Warning: Could not read original plugin.json (#{inspect(read_error)}), skipping field restoration"
          )

          json
      end
    else
      IO.puts(
        "Warning: Original plugin.json not found at #{plugin_path}, skipping field restoration"
      )

      json
    end
  end

  defp process_fields_update(json, fields_content, original_fields) do
    case parse_fields_txt(fields_content) do
      {:ok, parsed_fields} ->
        case validate_fields_changes(parsed_fields, original_fields) do
          {:ok, changes} ->
            if has_caption_or_key_changes?(changes) do
              show_changes_and_confirm(changes, parsed_fields, original_fields, json)
            else
              apply_fields_update(json, parsed_fields, original_fields)
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
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

  defp has_caption_or_key_changes?(changes) do
    Enum.any?(changes, fn change ->
      change.caption_changed or change.key_changed
    end)
  end

  defp show_changes_and_confirm(changes, parsed_fields, original_fields, json) do
    caption_changes = Enum.filter(changes, & &1.caption_changed)
    key_changes = Enum.filter(changes, & &1.key_changed)

    if length(caption_changes) > 0 or length(key_changes) > 0 do
      IO.puts("\n📝 Field changes detected:")

      if length(caption_changes) > 0 do
        IO.puts("\n  Caption changes:")

        Enum.each(caption_changes, fn change ->
          IO.puts("    #{change.key}: \"#{change.original_caption}\" → \"#{change.caption}\"")
        end)
      end

      if length(key_changes) > 0 do
        IO.puts("\n  Key changes:")

        Enum.each(key_changes, fn change ->
          IO.puts("    \"#{change.original_key}\" → \"#{change.key}\"")
        end)
      end

      IO.puts("\nDo you want to apply these changes? (y/N): ")
      response = IO.gets("") |> String.trim() |> String.downcase()

      if response in ["y", "yes"] do
        apply_fields_update(json, parsed_fields, original_fields)
      else
        IO.puts("Field changes cancelled by user.")
        {:error, "user_cancelled_field_changes"}
      end
    else
      apply_fields_update(json, parsed_fields, original_fields)
    end
  end

  defp apply_fields_update(json, parsed_fields, original_fields) do
    updated_fields =
      parsed_fields
      |> Enum.reduce(%{}, fn parsed_field, acc ->
        original_field_data = original_fields[parsed_field.key]

        updated_field_data =
          original_field_data
          |> Map.put("caption", parsed_field.caption)
          |> Map.put("rank", parsed_field.rank)

        Map.put(acc, parsed_field.key, updated_field_data)
      end)

    IO.puts("✅ Fields updated with new order and changes")
    Map.put(json, "fields", updated_fields)
  end
end
