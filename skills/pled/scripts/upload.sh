#!/usr/bin/env bash
# Upload a file to Bubble.io CDN and register it as an asset

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

check_env
check_deps

if [[ $# -lt 1 ]]; then
  error "Usage: pled upload <file_path>"
  exit 1
fi

FILE_PATH="$1"

if [[ ! -f "src/plugin.json" ]]; then
  error "src/plugin.json not found. Run 'pled pull' first."
  exit 1
fi

if [[ ! -f "$FILE_PATH" ]]; then
  error "File '$FILE_PATH' does not exist."
  exit 1
fi

echo "Uploading $FILE_PATH..."

# Upload to CDN
cdn_url=$(upload_file_to_cdn "$FILE_PATH")

info "File uploaded successfully!"
echo "CDN URL: $cdn_url"

# Add asset to plugin.json
step "Adding asset to plugin.json..."

# Get existing asset keys
existing_keys=$(jq -r '.assets // {} | keys[]' src/plugin.json 2>/dev/null || true)

# Generate next asset key
asset_key=$(next_asset_key "$existing_keys")
filename=$(basename "$FILE_PATH")

# Update plugin.json
tmp=$(jq \
  --arg key "$asset_key" \
  --arg name "$filename" \
  --arg url "$cdn_url" \
  '.assets = (.assets // {} | .[$key] = {"name": $name, "url": $url})' \
  src/plugin.json)
echo "$tmp" > src/plugin.json

info "Asset '$filename' added as $asset_key"
info "Upload completed"
