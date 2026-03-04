#!/usr/bin/env bash
# Shared utilities for pled scripts

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print helpers (all go to stderr so they don't pollute JSON output)
info()  { echo -e "${GREEN}✓${NC} $*" >&2; }
warn()  { echo -e "${YELLOW}⚠${NC} $*" >&2; }
error() { echo -e "${RED}✗${NC} $*" >&2; }
step()  { echo -e "${CYAN}→${NC} $*" >&2; }

# Load PLUGIN_ID from .plugin_id file, falling back to env var
load_plugin_id() {
  if [[ -z "${PLUGIN_ID:-}" && -f .plugin_id ]]; then
    PLUGIN_ID=$(cat .plugin_id | tr -d '[:space:]')
    export PLUGIN_ID
  fi
}

# Extract plugin ID from a Bubble URL or raw ID string
# Accepts: full URL, just the ID, or URL with extra params
extract_plugin_id() {
  local input="$1"
  # If it looks like a URL, extract the id param
  if [[ "$input" == *"bubble.io"* ]]; then
    local extracted
    extracted=$(echo "$input" | sed -n 's/.*[?&]id=\([0-9]*x[0-9]*\).*/\1/p')
    if [[ -n "$extracted" ]]; then
      echo "$extracted"
      return
    fi
  fi
  # Otherwise treat as raw ID (validate format: digits x digits)
  if [[ "$input" =~ ^[0-9]+x[0-9]+$ ]]; then
    echo "$input"
    return
  fi
  echo ""
}

# Check required environment variables
check_env() {
  load_plugin_id
  local missing=0
  if [[ -z "${PLUGIN_ID:-}" ]]; then
    error "PLUGIN_ID not found"
    echo "  Create a .plugin_id file: pled init <bubble-plugin-url>"
    echo "  Or set PLUGIN_ID as an environment variable."
    missing=1
  fi
  if [[ -z "${BUBBLE_COOKIE:-}" ]]; then
    error "BUBBLE_COOKIE is not set"
    echo "  Set BUBBLE_COOKIE as a global environment variable (e.g. in ~/.zshrc or ~/.bashrc)."
    missing=1
  fi
  if [[ $missing -eq 1 ]]; then
    exit 1
  fi
}

# Check required dependencies
check_deps() {
  local missing=0
  for cmd in jq curl; do
    if ! command -v "$cmd" &>/dev/null; then
      error "Missing dependency: $cmd"
      missing=1
    fi
  done
  if [[ $missing -eq 1 ]]; then
    exit 1
  fi
}

# Slugify a string: lowercase, replace non-alphanumeric with hyphens, collapse multiples
slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//'
}

# Remove Bubble function wrappers from JS code
# Strips: (async )?function(...) { ... } outer wrapper
remove_bubbleisms() {
  local input="$1"
  if [[ -z "$input" || "$input" == "null" ]]; then
    echo ""
    return
  fi
  echo "$input" | sed -E '1s/^(async )?function\([^)]*\) \{//' | sed -E '$ s/\}[[:space:]]*$//' | sed -E 's/^[[:space:]]*$//' | sed '1{
/^$/d
}'
}

# Fetch plugin data from Bubble API
fetch_plugin() {
  local url="https://bubble.io/appeditor/get_plugin?id=${PLUGIN_ID}"
  local response
  response=$(curl -s -w "\n%{http_code}" \
    -H "cookie: ${BUBBLE_COOKIE}" \
    -H "user-agent: Pled-Bash/1.0" \
    "$url")

  local http_code
  http_code=$(echo "$response" | tail -1)
  local body
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" != "200" ]]; then
    error "Failed to fetch plugin: HTTP $http_code"
    exit 1
  fi

  echo "$body"
}

# Save plugin data to Bubble API
save_plugin() {
  step "Uploading plugin..."
  local content
  content=$(cat dist/plugin.json)

  local payload
  payload=$(jq -n --arg id "$PLUGIN_ID" --argjson raw "$content" '{"id": $id, "raw": $raw}')

  local response
  response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "cookie: ${BUBBLE_COOKIE}" \
    -H "content-type: application/json" \
    -d "$payload" \
    "https://bubble.io/appeditor/save_plugin")

  local http_code
  http_code=$(echo "$response" | tail -1)

  if [[ "$http_code" == "200" ]]; then
    info "Plugin uploaded successfully"
  else
    error "Plugin upload failed: HTTP $http_code"
    exit 1
  fi
}

# Upload a file to Bubble CDN
upload_file_to_cdn() {
  local file_path="$1"
  local file_type="${2:-text/javascript}"
  local filename
  filename=$(basename "$file_path")

  local encoded
  encoded=$(base64 < "$file_path")

  local payload
  payload=$(jq -n \
    --arg app_version "live" \
    --arg type "$file_type" \
    --arg appname "meta" \
    --arg contents "$encoded" \
    --arg name "$filename" \
    '{app_version: $app_version, type: $type, appname: $appname, contents: $contents, name: $name}')

  local response
  response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "cookie: ${BUBBLE_COOKIE}" \
    -H "content-type: application/json; charset=utf-8" \
    -d "$payload" \
    "https://bubble.io/fileupload")

  local http_code
  http_code=$(echo "$response" | tail -1)
  local body
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" == "200" ]]; then
    echo "$body"
  else
    error "File upload failed: HTTP $http_code"
    exit 1
  fi
}

# Generate next asset key (AAA, AAB, ..., AAZ, ABA, ...)
next_asset_key() {
  local existing_keys="$1"  # newline-separated list of existing keys

  if [[ -z "$existing_keys" ]]; then
    echo "AAA"
    return
  fi

  # Get the last valid 3-letter uppercase key
  local last_key
  last_key=$(echo "$existing_keys" | grep -E '^[A-Z]{3}$' | sort | tail -1)

  if [[ -z "$last_key" ]]; then
    echo "AAA"
    return
  fi

  # Increment the key
  local c1 c2 c3
  c1=$(printf '%d' "'${last_key:0:1}")
  c2=$(printf '%d' "'${last_key:1:1}")
  c3=$(printf '%d' "'${last_key:2:1}")

  local Z
  Z=$(printf '%d' "'Z")

  if [[ $c3 -lt $Z ]]; then
    c3=$((c3 + 1))
  elif [[ $c2 -lt $Z ]]; then
    c2=$((c2 + 1))
    c3=$(printf '%d' "'A")
  elif [[ $c1 -lt $Z ]]; then
    c1=$((c1 + 1))
    c2=$(printf '%d' "'A")
    c3=$(printf '%d' "'A")
  else
    error "Asset key space exhausted (reached ZZZ)"
    exit 1
  fi

  printf '%b%b%b' "\\$(printf '%03o' $c1)" "\\$(printf '%03o' $c2)" "\\$(printf '%03o' $c3)"
}

# Save remote snapshot for change detection
save_snapshot() {
  local plugin_data="$1"
  echo "$plugin_data" > .src.json
}

# Compare current remote with local snapshot
# Returns: "no_changes" or "changes_detected"
check_remote_changes() {
  if [[ ! -f .src.json ]]; then
    echo "no_snapshot"
    return
  fi

  local current_remote
  current_remote=$(fetch_plugin)

  # Compare using sorted, normalized JSON
  local local_hash remote_hash
  local_hash=$(jq -cS '.' .src.json | shasum -a 256 | cut -d' ' -f1)
  remote_hash=$(echo "$current_remote" | jq -cS '.' | shasum -a 256 | cut -d' ' -f1)

  if [[ "$local_hash" == "$remote_hash" ]]; then
    echo "no_changes"
  else
    echo "changes_detected"
  fi
}
