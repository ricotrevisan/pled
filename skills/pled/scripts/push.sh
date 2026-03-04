#!/usr/bin/env bash
# Encode local files and push to Bubble.io

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/encode.sh"

check_env
check_deps

# Parse flags
FORCE=false
for arg in "$@"; do
  case "$arg" in
    --force|-f) FORCE=true ;;
  esac
done

echo "Pushing..."

# Check for remote changes unless --force
if [[ "$FORCE" != "true" ]]; then
  step "Checking for remote changes..."
  remote_status=$(check_remote_changes)

  case "$remote_status" in
    "no_changes")
      # All good, proceed
      ;;
    "no_snapshot")
      warn "No baseline found. Run 'pled pull' first to create baseline."
      warn "Or use --force to skip this check."
      echo ""
      read -rp "Continue with push anyway? [y/N]: " answer
      case "${answer,,}" in
        y|yes) ;;
        *) echo "Push aborted."; exit 1 ;;
      esac
      ;;
    "changes_detected")
      warn "Remote changes detected!"
      echo ""
      echo "Options:"
      echo "  1. Pull first to get remote changes: pled pull"
      echo "  2. Force push (overwrites remote): pled push --force"
      echo "  3. Abort this push"
      echo ""
      read -rp "Continue with push? [y/N]: " answer
      case "${answer,,}" in
        y|yes) ;;
        *) echo "Push aborted."; exit 1 ;;
      esac
      ;;
  esac
fi

# Encode
encode_plugin "src" "dist"

# Upload
save_plugin

# Update snapshot after successful push
step "Updating snapshot..."
plugin_data=$(fetch_plugin)
save_snapshot "$plugin_data"

info "Push completed"
