#!/usr/bin/env bash
# Show environment, authentication, and sync status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

check_deps
load_plugin_id

echo ""
echo "Environment:"

env_ok=true

if [[ -n "${PLUGIN_ID:-}" ]]; then
  if [[ -f .plugin_id ]]; then
    info "PLUGIN_ID: $PLUGIN_ID (from .plugin_id)"
  else
    info "PLUGIN_ID: $PLUGIN_ID (from env var)"
  fi
else
  error "PLUGIN_ID not found (no .plugin_id file or env var)"
  env_ok=false
fi

if [[ -n "${BUBBLE_COOKIE:-}" ]]; then
  info "BUBBLE_COOKIE is set (${#BUBBLE_COOKIE} chars)"
else
  error "BUBBLE_COOKIE is not set"
  env_ok=false
fi

echo ""
echo "Authentication:"

if [[ "$env_ok" != "true" ]]; then
  warn "Cannot verify (missing environment variables)"
  exit 1
fi

# Try to fetch plugin to verify auth
if plugin_data=$(fetch_plugin 2>/dev/null); then
  info "Cookie is valid"
else
  error "Cookie is invalid or expired"
  exit 1
fi

echo ""
echo "Sync Status:"

if [[ ! -f .src.json ]]; then
  warn "No baseline found (run 'pled pull' first)"
  exit 0
fi

# Compare
local_hash=$(jq -cS '.' .src.json | shasum -a 256 | cut -d' ' -f1)
remote_hash=$(echo "$plugin_data" | jq -cS '.' | shasum -a 256 | cut -d' ' -f1)

if [[ "$local_hash" == "$remote_hash" ]]; then
  info "Local matches remote"
else
  warn "Local differs from remote"
  echo "  Run 'pled pull' to update, or 'pled push --force' to overwrite."
fi
