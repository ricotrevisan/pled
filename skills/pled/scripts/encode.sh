#!/usr/bin/env bash
# Encode src/ files into dist/plugin.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/encode.sh"

check_deps

echo "Encoding..."
encode_plugin "src" "dist"
