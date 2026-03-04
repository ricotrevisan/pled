#!/usr/bin/env bash
# Decode plugin JSON into local src/ file structure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Decode a full plugin JSON blob into src/
decode_plugin() {
  local plugin_data="$1"
  local base_dir="${2:-.}"

  decode_elements "$plugin_data" "$base_dir"
  decode_actions "$plugin_data" "$base_dir"
  decode_html_header "$plugin_data" "$base_dir"
  clean_plugin_json "$base_dir"
}

# Extract shared HTML header
decode_html_header() {
  local plugin_data="$1"
  local base_dir="$2"

  local snippet
  snippet=$(echo "$plugin_data" | jq -r '.html_header.snippet // empty')

  if [[ -n "$snippet" ]]; then
    echo "$snippet" > "$base_dir/src/shared.html"
  fi
}

# Decode all elements
decode_elements() {
  local plugin_data="$1"
  local base_dir="$2"
  local elements_dir="$base_dir/src/elements"

  # Get element keys
  local keys
  keys=$(echo "$plugin_data" | jq -r '.plugin_elements // {} | keys[]' 2>/dev/null || true)

  if [[ -z "$keys" ]]; then
    return
  fi

  while IFS= read -r key; do
    decode_element "$plugin_data" "$key" "$elements_dir"
  done <<< "$keys"
}

# Decode a single element
decode_element() {
  local plugin_data="$1"
  local key="$2"
  local elements_dir="$3"

  local display
  display=$(echo "$plugin_data" | jq -r ".plugin_elements[\"$key\"].display // \"$key\"")
  local slug
  slug=$(slugify "$display")

  local element_dir="$elements_dir/${slug}-${key}"
  mkdir -p "$element_dir"

  # Extract JS functions
  local func
  for func in initialize preview reset update; do
    local fn_body
    fn_body=$(echo "$plugin_data" | jq -r ".plugin_elements[\"$key\"].code.${func}.fn // empty")
    remove_bubbleisms "$fn_body" > "$element_dir/${func}.js"
  done

  # Extract HTML header
  local html_snippet
  html_snippet=$(echo "$plugin_data" | jq -r ".plugin_elements[\"$key\"].headers.snippet // empty")
  echo "$html_snippet" > "$element_dir/headers.html"

  # Extract element actions
  decode_element_actions "$plugin_data" "$key" "$element_dir"

  # Extract fields
  decode_element_fields "$plugin_data" "$key" "$element_dir"

  # Write cleaned element JSON (without code and headers)
  local cleaned_actions
  cleaned_actions=$(echo "$plugin_data" | jq -r ".plugin_elements[\"$key\"].actions // {} | to_entries | map({key: .key, value: (.value | del(.code))}) | from_entries")

  echo "$plugin_data" | jq ".plugin_elements[\"$key\"] | del(.code) | del(.headers) | .actions = $cleaned_actions" \
    > "$element_dir/${key}.json"
}

# Decode element actions (JS files)
decode_element_actions() {
  local plugin_data="$1"
  local element_key="$2"
  local element_dir="$3"

  local action_keys
  action_keys=$(echo "$plugin_data" | jq -r ".plugin_elements[\"$element_key\"].actions // {} | keys[]" 2>/dev/null || true)

  if [[ -z "$action_keys" ]]; then
    return
  fi

  local actions_dir="$element_dir/actions"
  mkdir -p "$actions_dir"

  while IFS= read -r action_key; do
    local caption
    caption=$(echo "$plugin_data" | jq -r ".plugin_elements[\"$element_key\"].actions[\"$action_key\"].caption // \"$action_key\"")
    local action_slug
    action_slug=$(slugify "$caption")

    local fn_body
    fn_body=$(echo "$plugin_data" | jq -r ".plugin_elements[\"$element_key\"].actions[\"$action_key\"].code.fn // empty")
    remove_bubbleisms "$fn_body" > "$actions_dir/${action_slug}-${action_key}.js"
  done <<< "$action_keys"
}

# Decode element fields into fields.txt
decode_element_fields() {
  local plugin_data="$1"
  local element_key="$2"
  local element_dir="$3"

  local fields_json
  fields_json=$(echo "$plugin_data" | jq -r ".plugin_elements[\"$element_key\"].fields // {}")

  local field_count
  field_count=$(echo "$fields_json" | jq 'length')

  if [[ "$field_count" == "0" ]]; then
    return
  fi

  # Sort by rank, format as "caption (key)"
  echo "$fields_json" | jq -r 'to_entries | sort_by(.value.rank) | .[] | "\(.value.caption) (\(.key))"' \
    > "$element_dir/fields.txt"
}

# Decode all standalone actions
decode_actions() {
  local plugin_data="$1"
  local base_dir="$2"
  local actions_dir="$base_dir/src/actions"

  local keys
  keys=$(echo "$plugin_data" | jq -r '.plugin_actions // {} | keys[]' 2>/dev/null || true)

  if [[ -z "$keys" ]]; then
    return
  fi

  while IFS= read -r key; do
    decode_action "$plugin_data" "$key" "$actions_dir"
  done <<< "$keys"
}

# Decode a single standalone action
decode_action() {
  local plugin_data="$1"
  local key="$2"
  local actions_dir="$3"

  local display
  display=$(echo "$plugin_data" | jq -r ".plugin_actions[\"$key\"].display // \"$key\"")
  local slug
  slug=$(slugify "$display")

  local action_dir="$actions_dir/${slug}-${key}"
  mkdir -p "$action_dir"

  # Extract client and server JS
  local func
  for func in client server; do
    local fn_body
    fn_body=$(echo "$plugin_data" | jq -r ".plugin_actions[\"$key\"].code.${func}.fn // empty")
    remove_bubbleisms "$fn_body" > "$action_dir/${func}.js"
  done

  # Write cleaned action JSON (without server/client code)
  local code_without_fns
  code_without_fns=$(echo "$plugin_data" | jq ".plugin_actions[\"$key\"].code | del(.server) | del(.client)")

  echo "$plugin_data" | jq ".plugin_actions[\"$key\"] | .code = $code_without_fns" \
    > "$action_dir/${slug}.json"
}

# Remove plugin_elements, plugin_actions, html_header from plugin.json
clean_plugin_json() {
  local base_dir="$1"
  local plugin_path="$base_dir/src/plugin.json"

  if [[ -f "$plugin_path" ]]; then
    local tmp
    tmp=$(jq 'del(.html_header, .plugin_actions, .plugin_elements)' "$plugin_path")
    echo "$tmp" > "$plugin_path"
  fi
}
