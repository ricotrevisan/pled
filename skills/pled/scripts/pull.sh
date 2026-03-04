#!/usr/bin/env bash
# Fetch plugin from Bubble.io and decode to local src/ files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/decode.sh"

check_env
check_deps

# Parse flags
WIPE=false
for arg in "$@"; do
  case "$arg" in
    --wipe|-w) WIPE=true ;;
  esac
done

echo "Pulling plugin..."

# Wipe if requested
if [[ "$WIPE" == "true" ]]; then
  step "Wiping src and dist directories..."
  rm -rf src dist
fi

# Fetch plugin data
step "Fetching plugin from Bubble.io..."
plugin_data=$(fetch_plugin)

# Create src directory and write raw plugin.json
mkdir -p src
echo "$plugin_data" | jq '.' > src/plugin.json

# Save remote snapshot for change detection
save_snapshot "$plugin_data"

# Decode into file structure
step "Decoding plugin..."
decode_plugin "$plugin_data" "."

info "Pull completed"
