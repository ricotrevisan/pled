#!/usr/bin/env bash
# Encode local src/ files back into Bubble-compatible plugin JSON

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Main encode function: src/ → dist/plugin.json
encode_plugin() {
  local src_dir="${1:-src}"
  local dist_dir="${2:-dist}"

  if [[ ! -d "$src_dir" ]]; then
    error "No src directory found. Run 'pled pull' first."
    exit 1
  fi

  mkdir -p "$dist_dir"

  step "Encoding plugin..."

  # Start with plugin.json base
  local output_json
  output_json=$(cat "$src_dir/plugin.json")

  # Encode elements
  output_json=$(encode_elements "$output_json" "$src_dir/elements")

  # Encode actions
  output_json=$(encode_actions "$output_json" "$src_dir/actions")

  # Encode shared HTML
  output_json=$(encode_html "$output_json" "$src_dir")

  # Write output
  echo "$output_json" | jq '.' > "$dist_dir/plugin.json"
  info "dist/plugin.json generated"
}

# Encode all elements
encode_elements() {
  local json="$1"
  local elements_dir="$2"

  if [[ ! -d "$elements_dir" ]]; then
    echo "$json"
    return
  fi

  local elements_json="{}"

  for element_dir in "$elements_dir"/*/; do
    [[ -d "$element_dir" ]] || continue

    local dirname
    dirname=$(basename "$element_dir")

    # Skip hidden directories
    [[ "$dirname" == .* ]] && continue

    local key
    key=$(echo "$dirname" | rev | cut -d'-' -f1 | rev)

    step "Encoding element: $dirname"

    local element_json
    element_json=$(encode_element "$element_dir" "$key")

    elements_json=$(echo "$elements_json" | jq --arg key "$key" --argjson val "$element_json" '.[$key] = $val')
  done

  echo "$json" | jq --argjson elements "$elements_json" '.plugin_elements = $elements'
}

# Encode a single element
encode_element() {
  local element_dir="$1"
  local key="$2"

  # Read element metadata JSON
  local element_json
  element_json=$(cat "$element_dir/${key}.json")

  # Generate code block from JS files
  local code_json="{}"

  # initialize.js
  if [[ -f "$element_dir/initialize.js" ]]; then
    code_json=$(echo "$code_json" | jq --rawfile content "$element_dir/initialize.js" \
      '.initialize = {"fn": ("function(instance, context) {\n" + $content + "\n}")}')
  fi

  # update.js
  if [[ -f "$element_dir/update.js" ]]; then
    code_json=$(echo "$code_json" | jq --rawfile content "$element_dir/update.js" \
      '.update = {"fn": ("function(instance, properties, context) {\n" + $content + "\n}")}')
  fi

  # preview.js
  if [[ -f "$element_dir/preview.js" ]]; then
    code_json=$(echo "$code_json" | jq --rawfile content "$element_dir/preview.js" \
      '.preview = {"fn": ("function(instance, properties) {\n" + $content + "\n}")}')
  fi

  # reset.js
  if [[ -f "$element_dir/reset.js" ]]; then
    code_json=$(echo "$code_json" | jq --rawfile content "$element_dir/reset.js" \
      '.reset = {"fn": ("function(instance, context) {\n" + $content + "\n}")}')
  fi

  element_json=$(echo "$element_json" | jq --argjson code "$code_json" '.code = $code')

  # HTML headers
  if [[ -f "$element_dir/headers.html" ]]; then
    local snippet
    snippet=$(cat "$element_dir/headers.html")
    element_json=$(echo "$element_json" | jq --arg snippet "$snippet" '.headers = {"snippet": $snippet}')
  fi

  # Element actions
  element_json=$(encode_element_actions "$element_json" "$element_dir")

  # Fields from fields.txt
  element_json=$(encode_element_fields "$element_json" "$element_dir")

  echo "$element_json"
}

# Encode element actions from JS files
encode_element_actions() {
  local json="$1"
  local element_dir="$2"
  local actions_dir="$element_dir/actions"

  if [[ ! -d "$actions_dir" ]]; then
    echo "$json"
    return
  fi

  # Check if the element has actions in JSON
  local has_actions
  has_actions=$(echo "$json" | jq 'has("actions")')

  if [[ "$has_actions" != "true" ]]; then
    echo "$json"
    return
  fi

  local existing_actions
  existing_actions=$(echo "$json" | jq '.actions')

  for js_file in "$actions_dir"/*.js; do
    [[ -f "$js_file" ]] || continue

    local filename
    filename=$(basename "$js_file" .js)
    local action_key
    action_key=$(echo "$filename" | rev | cut -d'-' -f1 | rev)

    # Check if action exists in JSON
    local action_exists
    action_exists=$(echo "$existing_actions" | jq --arg key "$action_key" 'has($key)')

    if [[ "$action_exists" == "true" ]]; then
      existing_actions=$(echo "$existing_actions" | jq \
        --arg key "$action_key" \
        --rawfile content "$js_file" \
        '.[$key].code = {"fn": ("function(instance, properties, context) {\n" + $content + "\n}")}')
    else
      warn "Action key '$action_key' not found in element JSON, skipping $filename.js"
    fi
  done

  echo "$json" | jq --argjson actions "$existing_actions" '.actions = $actions'
}

# Encode fields from fields.txt (preserve rank ordering)
encode_element_fields() {
  local json="$1"
  local element_dir="$2"
  local fields_path="$element_dir/fields.txt"

  if [[ ! -f "$fields_path" ]]; then
    echo "$json"
    return
  fi

  local existing_fields
  existing_fields=$(echo "$json" | jq '.fields // {}')
  local field_count
  field_count=$(echo "$existing_fields" | jq 'length')

  if [[ "$field_count" == "0" ]]; then
    # Try to restore fields from src/plugin.json original data
    local element_key
    element_key=$(basename "$element_dir" | rev | cut -d'-' -f1 | rev)
    local plugin_path
    plugin_path=$(dirname "$(dirname "$element_dir")")/plugin.json

    if [[ -f "$plugin_path" ]]; then
      existing_fields=$(jq -r ".plugin_elements[\"$element_key\"].fields // {}" "$plugin_path" 2>/dev/null || echo "{}")
      field_count=$(echo "$existing_fields" | jq 'length')
      if [[ "$field_count" == "0" ]]; then
        echo "$json"
        return
      fi
    else
      echo "$json"
      return
    fi
  fi

  # Parse fields.txt and update ranks/captions
  local rank=0
  local updated_fields="$existing_fields"

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    # Parse "caption (key)" format
    local caption field_key
    local re='^(.+) \(([^)]+)\)$'
    if [[ "$line" =~ $re ]]; then
      caption="${BASH_REMATCH[1]}"
      field_key="${BASH_REMATCH[2]}"
    else
      warn "Malformed fields.txt line: $line"
      continue
    fi

    # Check field exists
    local field_exists
    field_exists=$(echo "$updated_fields" | jq --arg key "$field_key" 'has($key)')

    if [[ "$field_exists" == "true" ]]; then
      updated_fields=$(echo "$updated_fields" | jq \
        --arg key "$field_key" \
        --arg caption "$caption" \
        --argjson rank "$rank" \
        '.[$key].caption = $caption | .[$key].rank = $rank')
      rank=$((rank + 1))
    else
      warn "Field key '$field_key' not found in element JSON"
    fi
  done < "$fields_path"

  echo "$json" | jq --argjson fields "$updated_fields" '.fields = $fields'
}

# Encode all standalone actions
encode_actions() {
  local json="$1"
  local actions_dir="$2"

  if [[ ! -d "$actions_dir" ]]; then
    echo "$json" | jq '.plugin_actions = {}'
    return
  fi

  local actions_json="{}"

  for action_dir in "$actions_dir"/*/; do
    [[ -d "$action_dir" ]] || continue

    local dirname
    dirname=$(basename "$action_dir")
    [[ "$dirname" == .* ]] && continue

    local key
    key=$(echo "$dirname" | rev | cut -d'-' -f1 | rev)

    step "Encoding action: $dirname"

    local action_json
    action_json=$(encode_action "$action_dir" "$key")

    actions_json=$(echo "$actions_json" | jq --arg key "$key" --argjson val "$action_json" '.[$key] = $val')
  done

  echo "$json" | jq --argjson actions "$actions_json" '.plugin_actions = $actions'
}

# Encode a single standalone action
encode_action() {
  local action_dir="$1"
  local key="$2"

  # Find the JSON metadata file
  local json_file
  json_file=$(find "$action_dir" -maxdepth 1 -name "*.json" | head -1)

  if [[ -z "$json_file" ]]; then
    error "No JSON metadata file found in $action_dir"
    exit 1
  fi

  local action_json
  action_json=$(cat "$json_file")

  # Get existing code block (non-function properties)
  local original_code
  original_code=$(echo "$action_json" | jq '.code // {}')
  local base_code
  base_code=$(echo "$original_code" | jq 'del(.server) | del(.client)')

  # Process server.js
  if [[ -f "$action_dir/server.js" ]]; then
    local existing_server
    existing_server=$(echo "$original_code" | jq '.server // {}')
    base_code=$(echo "$base_code" | jq \
      --argjson existing "$existing_server" \
      --rawfile content "$action_dir/server.js" \
      '.server = ($existing + {"fn": ("async function(properties, context) {\n" + $content + "\n}")})')
  fi

  # Process client.js
  if [[ -f "$action_dir/client.js" ]]; then
    local existing_client
    existing_client=$(echo "$original_code" | jq '.client // {}')
    base_code=$(echo "$base_code" | jq \
      --argjson existing "$existing_client" \
      --rawfile content "$action_dir/client.js" \
      '.client = ($existing + {"fn": ("function(properties, context) {\n" + $content + "\n}")})')
  fi

  echo "$action_json" | jq --argjson code "$base_code" '.code = $code'
}

# Encode shared HTML
encode_html() {
  local json="$1"
  local src_dir="$2"
  local html_path="$src_dir/shared.html"

  if [[ -f "$html_path" ]]; then
    local snippet
    snippet=$(cat "$html_path")
    echo "$json" | jq --arg snippet "$snippet" '.html_header = {"snippet": $snippet}'
  else
    echo "$json"
  fi
}
