# Pled

A CLI for developing Bubble.io plugins locally with real files and version control.

Pled pulls your plugin from Bubble, decodes it into a clean `src/` tree (JS files with readable names), then encodes and pushes changes back to Bubble. It's designed for Bubble plugin builders who want a faster edit-test loop and better tooling than the web editor.

## Quickstart

- You're comfortable with Bubble plugins (elements/actions/fields) but new(ish) to JavaScript.
- You want to edit JS locally and keep your plugin in Git.

1) Initialize a Pled project
Create a directory per plugin and initialize it:

```sh
mkdir my-bubble-plugin
cd my-bubble-plugin
pled init https://bubble.io/plugin_editor?id=some_bubble_plugin
```

- This creates helpful scaffolding:
  - .plugin_id (stores the plugin ID — not a secret, commit it)
  - .gitignore
  - src/, dist/, and support files (e.g., lib/, llm.md)

2) Set BUBBLE_COOKIE
- Pled requires a `BUBBLE_COOKIE` environment variable with your authenticated Bubble cookie string.
- Add it to your shell profile (`~/.zshrc` or `~/.bashrc`):
    export BUBBLE_COOKIE="meta_xxx=...; meta_yyy=...; ..." (see below for instructions)

Security reminder: Your BUBBLE_COOKIE grants access to your Bubble account. Treat it like a secret. Rotate it if needed.

3) Pull your plugin
- Fetch current plugin config and decode to local files:
    pled pull

4) Edit locally
- Open `src/` in your editor. You'll see:
  - src/plugin.json        → metadata for your plugin
  - src/shared.html        → shared HTML snippets (if any)
  - src/elements/...       → elements with JS files:
      - initialize.js
      - update.js
      - reset.js
      - preview.js
      - actions/...        → element-specific actions (JS files)
  - src/actions/...        → standalone actions (client.js, server.js)

- Typical edits:
  - Modify element lifecycle files (`initialize.js`, `update.js`, etc.)
  - Implement actions (`client.js` for browser, `server.js` for server)
  - Keep function signatures and Bubble-provided arguments intact

5) Push changes to Bubble
- Encode local files back to Bubble format and upload:
    pled push

- If you know you want to overwrite remote changes (e.g., you own the latest source of truth), use:
    pled push --force

6) Fast inner loop (optional)
- Keep local files and Bubble in sync while you work:
    pled watch
- Saves in `src/` are debounced and pushed when the remote is clean.
- Changes made in the Bubble editor are pulled when nothing local is unpushed.
- If both sides changed, watch pauses and prints how to resolve it, then resumes
  on its own once you do.
- `pled watch --interval 60` checks Bubble once a minute instead of every 15s.

## Mental model: how Pled works

- Pull: Bubble API → Pled Decoder → local `src/` files with clean naming
- Edit: You change JS and metadata locally; commit to Git as needed
- Push: Local `src/` → Pled Encoder → Bubble API

Pled maintains round-trip fidelity: pulling and pushing won't scramble your plugin structure. It separates Bubble's embedded JS functions into individual files so you can work like a normal JS project.

## Installation

- macOS / Linux:
    chmod +x pled
    cp pled /usr/local/bin
- Windows:
  - Place `pled_windows.exe` somewhere on your PATH and rename to `pled.exe` if desired.

Verify:
    pled help

## Environment setup

- Required:
  - BUBBLE_COOKIE: The `meta_*` cookies from your logged-in Bubble session, concatenated by semicolons

- How to get BUBBLE_COOKIE:
  - Go to https://bubble.io and log in
  - Open the browser dev tools
  - go to the network tab,
  - find a call to `bubble.io`
  - go to "Headers"
  - scroll down to "Request Headers"
  - find the "Cookie"
  - copy the entire value or just the pairs where the key starts with `meta_`
  - add it to your shell profile (`~/.zshrc` or `~/.bashrc`) as `export BUBBLE_COOKIE="..."`

![get_bubble_cookie.png](get_bubble_cookie.png)

## Common workflows

- Start a new local workspace for an existing plugin:
    mkdir my-bubble-plugin && cd my-bubble-plugin
    pled init https://bubble.io/plugin_editor?id=1234x5678
    pled pull

- Edit and push:
    # modify files under src/
    pled push

- Two-way sync while editing:
    pled watch

- Build encoded JSON without uploading (for inspection/CI):
    pled encode
  - Outputs to `dist/plugin.json`

- Check for remote changes without pushing:
    pled check-remote

- Upload a specific asset to Bubble CDN:
    pled upload path/to/file.json

- Force push (overwrite remote):
    pled push --force

## CLI reference

Run:
    pled help

You should see:
    Bubble.io Plugin Development Tool
    version X.Y.Z

    Usage:
      pled init <url|id>    Initialize project with a Bubble plugin URL or ID
      pled pull             Fetch plugin from Bubble.io and save to src/plugin.json
      pled pull --wipe      Discard local changes and pull
      pled push             Encodes and then upload plugin to Bubble.io
      pled push --force     Force push, overwriting remote changes
      pled encode           Prepares the files to upload. Compiles src/ files into dist/plugin.json
      pled upload <file>    Upload a file to Bubble.io CDN
      pled watch            Keeps `src/` and Bubble in sync, pausing on conflicts
      pled check-remote     Check for remote changes without pushing
      pled status           Show environment, auth, and sync status

    Required Environment Variables:
      BUBBLE_COOKIE         Authentication cookie for Bubble.io

## Tips for Bubble builders (with beginner JS)

- Start with `update.js`: This is where you respond to property changes and redraw your element.
- Keep function arguments intact: Bubble calls your functions with specific parameters; don't remove them.
- Add small, targeted logs:
    console.log("[MyElement] update", properties);
- For actions, decide between:
  - client.js: runs in the browser (access to DOM/window)
  - server.js: runs server-side (no DOM; use Bubble server resources)
- Test one change at a time: push, then test in a Bubble test app.

## Troubleshooting

- 401/403 errors:
  - BUBBLE_COOKIE likely expired or not set for the bubble.io domain. Re-grab the cookie.

- Push rejects because of remote changes:
  - Pull first: `pled pull`
  - Or if you intend to overwrite: `pled push --force`

- Nothing is changing in Bubble:
  - Confirm you edited files under `src/` (not `dist/`)
  - Try `pled encode` and inspect `dist/plugin.json` to verify your changes are present.

- Watch doesn't trigger:
  - Only files under `src/` are watched.
  - Ensure your editor writes to disk and there's no file permission issue.

- Watch says it is paused:
  - Local and remote both changed. Run `pled pull --wipe` to drop local changes
    or `pled push --force` to overwrite the remote; watch resumes by itself.

## Project structure (local)

- src/plugin.json       → plugin metadata
- src/shared.html       → optional shared HTML
- src/elements/<name>/  → element folder
  - initialize.js
  - update.js
  - reset.js
  - preview.js
  - actions/            → element-specific actions (JS files)
- src/actions/<name>/   → standalone actions
  - client.js
  - server.js
- dist/plugin.json      → encoded output (generated by `pled encode`)

## Best practices

- Use Git from day one. Commit after successful pushes.
- Prefer small, incremental changes and test in Bubble often.
- Keep logs consistent and easy to search (prefix with your element/action name).
- Treat BUBBLE_COOKIE like a password; don't commit it to Git.

## License / Version

- Version: see `pled help` output
