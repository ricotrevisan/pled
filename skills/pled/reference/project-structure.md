# Project Structure

After running `pull`, the project has this layout:

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

## File Conventions

- `initialize.js` runs with `instance` and `context` — don't add the function wrapper, pled does it
- `update.js` runs with `instance`, `properties`, and `context`
- Element actions run with `instance`, `properties`, `context`
- Plugin actions: `client.js` → `function(properties, context)`, `server.js` → `async function(properties, context)`
- The `.src.json` snapshot file tracks remote state for change detection
