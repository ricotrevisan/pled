#!/usr/bin/env bash
# Watch src/ for changes and auto-push to Bubble.io

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

check_env
check_deps

# Check for fswatch
if ! command -v fswatch &>/dev/null; then
  error "fswatch is required for watch mode."
  echo "Install with: brew install fswatch (macOS) or apt-get install fswatch (Linux)"
  exit 1
fi

if [[ ! -d "src" ]]; then
  error "No src directory found. Run 'pled pull' first."
  exit 1
fi

echo ""
echo "  ___  _         _ "
echo " | _ \\| |___ __ | |"
echo " |  _/| / -_) _\`| |"
echo " |_|  |_\\___\\__,_|_|"
echo ""
echo "Watching src/ for changes... (Ctrl+C to stop)"
echo ""

# Debounce: collect events for 0.5 seconds before triggering push
PUSH_SCRIPT="$SCRIPT_DIR/push.sh"

fswatch -0 --latency 0.5 -r src/ | while IFS= read -r -d '' file; do
  echo ""
  step "Change detected: $(basename "$file")"

  # Run push with --force (skip remote check in watch mode)
  if bash "$PUSH_SCRIPT" --force; then
    info "Auto-push completed"
  else
    warn "Auto-push failed, will retry on next change"
  fi
done
