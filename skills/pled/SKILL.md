---
name: pled
description: "Bubble.io plugin development CLI. Pull plugin source from Bubble, edit locally as JS files, push back. Commands: init, pull, push, encode, upload, watch, check-remote, status. Use when working with Bubble.io plugins, editing plugin elements/actions, or syncing plugin code."
---

# Pled — Bubble.io Plugin Development Tool

A bash-based CLI for developing Bubble.io plugins locally with real files and version control.

## Setup

Requires: `jq`, `curl`, `fswatch` (macOS) or `inotifywait` (Linux).

```bash
# Check dependencies
command -v jq curl fswatch >/dev/null 2>&1 || echo "Missing dependencies"
```

## Environment & Configuration

**Plugin ID** is stored in a `.plugin_id` file (committed to repo — it's not a secret):

```bash
# Created automatically by init:
bash scripts/init.sh https://bubble.io/plugin_editor?id=1234x5678
# Or just the ID:
bash scripts/init.sh 1234x5678
```

**BUBBLE_COOKIE** must be set as a global environment variable (it IS a secret):

```bash
# In ~/.zshrc or ~/.bashrc:
export BUBBLE_COOKIE="meta_xxx=...; meta_yyy=..."
```

Falls back: if no `.plugin_id` file exists, `PLUGIN_ID` env var is checked.

## Commands

All scripts are in the `scripts/` directory relative to this skill.

### Init — scaffold a new plugin project

```bash
bash scripts/init.sh <bubble-plugin-url-or-id>
```

Accepts a Bubble plugin editor URL or a raw plugin ID. Extracts the ID, writes `.plugin_id`, and scaffolds the project structure.

### Pull — fetch plugin from Bubble and decode to local files

```bash
bash scripts/pull.sh
```

### Push — encode local files and upload to Bubble

```bash
bash scripts/push.sh          # with remote change detection
bash scripts/push.sh --force   # skip remote check
```

### Encode — compile src/ to dist/plugin.json without uploading

```bash
bash scripts/encode.sh
```

### Upload — upload a file to Bubble CDN

```bash
bash scripts/upload.sh path/to/file.js
```

### Watch — auto-push on file changes

```bash
bash scripts/watch.sh
```

### Check Remote — detect remote changes without pushing

```bash
bash scripts/check-remote.sh
```

### Status — show environment and sync status

```bash
bash scripts/status.sh
```

## Project Structure (after pull)

```
.plugin_id               # Plugin ID (committed to repo)
src/
├── plugin.json          # Plugin metadata (elements/actions stripped)
├── shared.html          # Shared HTML header
├── elements/
│   └── <name>-<KEY>/
│       ├── <KEY>.json   # Element metadata
│       ├── initialize.js
│       ├── update.js
│       ├── preview.js
│       ├── reset.js
│       ├── headers.html
│       ├── fields.txt
│       └── actions/
│           └── <action-name>-<KEY>.js
└── actions/
    └── <name>-<KEY>/
        ├── <name>.json  # Action metadata
        ├── client.js
        └── server.js
dist/
└── plugin.json          # Encoded output (generated)
```

## Workflow

1. `pled init <url>` → scaffold project, save plugin ID
2. `pled pull` → fetch and decode plugin
3. Edit JS files in `src/`
4. `pled push` → encode and upload
5. Or `pled watch` → auto-push on save

## Notes

- `initialize.js` runs with `instance` and `context` — don't add the function wrapper, pled does it
- `update.js` runs with `instance`, `properties`, and `context`
- Element actions run with `instance`, `properties`, `context`
- Plugin actions: `client.js` → `function(properties, context)`, `server.js` → `async function(properties, context)`
- The `.src.json` snapshot file tracks remote state for change detection
