#!/usr/bin/env bash
# Initialize a new Pled project structure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

echo "Initializing Pled project..."

# ── Plugin ID ─────────────────────────────────────────────

# Accept URL or ID as argument
if [[ $# -ge 1 ]]; then
  input="$1"
  plugin_id=$(extract_plugin_id "$input")
  if [[ -z "$plugin_id" ]]; then
    error "Could not extract plugin ID from: $input"
    echo ""
    echo "Expected formats:"
    echo "  https://bubble.io/plugin_editor?id=1234x5678"
    echo "  1234x5678"
    exit 1
  fi
  echo "$plugin_id" > .plugin_id
  info "Saved plugin ID to .plugin_id: $plugin_id"
elif [[ -f .plugin_id ]]; then
  warn ".plugin_id already exists: $(cat .plugin_id)"
else
  echo ""
  echo "Usage: pled init <bubble-plugin-url-or-id>"
  echo ""
  echo "Examples:"
  echo "  pled init https://bubble.io/plugin_editor?id=1234x5678"
  echo "  pled init 1234x5678"
  exit 1
fi

# ── .gitignore ────────────────────────────────────────────

GITIGNORE_ENTRIES=(".envrc" ".src.json" "lib/node_modules" "lib/dist*" "dist*")

if [[ -f .gitignore ]]; then
  existing=$(cat .gitignore)
  missing=()
  for entry in "${GITIGNORE_ENTRIES[@]}"; do
    if ! grep -qF "$entry" .gitignore; then
      missing+=("$entry")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    printf '%s\n' "${missing[@]}" >> .gitignore
    info "Updated .gitignore with: ${missing[*]}"
  else
    warn ".gitignore already contains all required entries, skipping..."
  fi
else
  printf '%s\n' "${GITIGNORE_ENTRIES[@]}" > .gitignore
  info "Created .gitignore"
fi

# ── AGENTS.md ─────────────────────────────────────────────

AGENTS_CONTENT='
# working with Pled

## Essential Context

- Project purpose: this is a Bubble.io plugin
- Core workflow: Pull → Edit locally → Push back to Bubble.
- You can run `pled watch` to automatically encode and push when there are changes to the `src/` directory.
- File structure: src/ contains decoded human-readable files, dist/ contains encoded Bubble JSON, lib/ contains any libraries that you might want to add to your project

## Key Commands & Usage

- Plugin ID is stored in `.plugin_id` (committed to repo)
- BUBBLE_COOKIE must be set as a global environment variable (it is the only secret)
- Main commands: pull, push, watch, encode, init
- Testing commands and patterns

## Development Guidelines

- when changing `lib/index.js`, run `npm run build` in the `lib/` directory, then rename the `lib/dist.js` file to the latest version (start at `dist-v01.js` and go up from there), the run `pled upload lib/dist-vVERSION.js`
- when making changes to an element'\''s `initialize.js` or `update.js`, in order to verify if the changes are working, use the Playwright MCP server and open the page listed in env var "TEST_URL"
- in initialize and update, you never have to add the standard bubble `function(properties...)`. Pled will do that automatically.
- `initialize.js` runs with `instance` and `context`
- `update.js` runs with `instance`, `properties`, and `context`
- if a `shared_keys` is `secure`, it is never available in the elements, only in server-side actions.
'

if [[ -f AGENTS.md ]]; then
  if grep -q "# working with Pled" AGENTS.md; then
    warn "AGENTS.md already contains Pled section, skipping..."
  else
    echo "$AGENTS_CONTENT" >> AGENTS.md
    info "Updated AGENTS.md"
  fi
else
  echo "$AGENTS_CONTENT" > AGENTS.md
  info "Created AGENTS.md"
fi

# ── lib/ directory ────────────────────────────────────────

mkdir -p lib
info "Created lib/ directory"

if [[ -f lib/package.json ]]; then
  warn "lib/package.json already exists, skipping..."
else
  cat > lib/package.json << 'EOF'
{
  "name": "my-plugin-package",
  "version": "0.0.1",
  "description": "",
  "main": "index.js",
  "scripts": {
    "build": "esbuild index.js --bundle --minify --outfile=dist.js"
  },
  "keywords": [],
  "author": "",
  "license": "ISC"
}
EOF
  info "Created lib/package.json"
fi

if [[ -f lib/index.js ]]; then
  warn "lib/index.js already exists, skipping..."
else
  touch lib/index.js
  info "Created lib/index.js"
fi

echo ""
echo "✓ Project initialized!"
echo ""
echo "Next steps:"
if [[ -z "${BUBBLE_COOKIE:-}" ]]; then
  echo "1. Set BUBBLE_COOKIE as a global env var (e.g. in ~/.zshrc)"
fi
echo "2. Run 'pled pull' to fetch your plugin from Bubble.io"
