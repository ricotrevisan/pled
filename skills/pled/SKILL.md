---
name: pled
description: "Bubble.io plugin development CLI. Pull plugin source from Bubble, edit locally as JS files, push back. Commands: init, pull, push, encode, upload, watch, check-remote, status. Use when working with Bubble.io plugins, editing plugin elements/actions, or syncing plugin code."
---

# Pled — Bubble.io Plugin Development Tool

A bash-based CLI for developing Bubble.io plugins locally with real files and version control.

## Setup

Requires: `jq`, `curl`, `fswatch` (macOS) or `inotifywait` (Linux).

```bash
command -v jq curl fswatch >/dev/null 2>&1 || echo "Missing dependencies"
```

## Environment

**Plugin ID** is stored in a `.plugin_id` file (committed to repo — it's not a secret):

```bash
bash scripts/init.sh https://bubble.io/plugin_editor?id=1234x5678
```

**BUBBLE_COOKIE** must be set as a global environment variable (it IS a secret):

```bash
export BUBBLE_COOKIE="meta_xxx=...; meta_yyy=..."
```

Falls back: if no `.plugin_id` file exists, `PLUGIN_ID` env var is checked.

## Workflow

1. `pled init <url>` → scaffold project, save plugin ID
2. `pled pull` → fetch and decode plugin
3. Edit JS files in `src/`
4. `pled push` → encode and upload
5. Or `pled watch` → auto-push on save

## Command Index

| Command | Description | Reference |
|---------|-------------|-----------|
| `init` | Scaffold a new plugin project | `reference/commands.md` |
| `pull` | Fetch plugin from Bubble and decode to local files | `reference/commands.md` |
| `push` | Encode local files and upload to Bubble | `reference/commands.md` |
| `encode` | Compile src/ to dist/plugin.json without uploading | `reference/commands.md` |
| `upload` | Upload a file to Bubble CDN | `reference/commands.md` |
| `watch` | Auto-push on file changes | `reference/commands.md` |
| `check-remote` | Detect remote changes without pushing | `reference/commands.md` |
| `status` | Show environment and sync status | `reference/commands.md` |

See `reference/project-structure.md` for the project layout and file conventions.
