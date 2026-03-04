#!/usr/bin/env bash
# Check for remote changes without pushing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

check_env
check_deps

echo "Checking for remote changes..."

result=$(check_remote_changes)

case "$result" in
  "no_changes")
    info "No remote changes detected"
    ;;
  "no_snapshot")
    warn "No baseline found. Run 'pled pull' first to create baseline."
    ;;
  "changes_detected")
    warn "Remote changes detected!"
    echo ""
    echo "Recommendations:"
    echo "  • Run 'pled pull' to incorporate remote changes"
    echo "  • Or use 'pled push --force' to overwrite remote changes"
    ;;
esac
