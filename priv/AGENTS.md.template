
# working with Pled

## Essential Context

- Project purpose: this is a Bubble.io plugin
- Core workflow: Pull → Edit locally → Push back to Bubble.
- You can run `pled watch` to automatically encode and push when there are changes to the `src/` directory.
- File structure: src/ contains decoded human-readable files, dist/ contains encoded Bubble JSON, lib/ contains any libraries that you might want to add to your project

## Key Commands & Usage

- Plugin ID is stored in `.plugin_id` (committed to repo)
- COOKIE must be set as a global environment variable (it is the only secret)
- Main commands: pull, push, watch, encode, init
- Testing commands and patterns

## Development Guidelines

- when changing `lib/index.js`, run `npm run build` in the `lib/` directory, then rename the `lib/dist.js` file to the latest version (start at `dist-v01.js` and go up from there), the run `pled upload lib/dist-vVERSION.js`
- when making changes to an element's `initialize.js` or `update.js`, in order to verify if the changes are working, use the Playwright MCP server and open the page listed in env var "TEST_URL"
- in initialize and update, you never have to add the standard bubble `function(properties...)`. Pled will do that automatically.
- `initialize.js` runs with `instance` and `context`
- `update.js` runs with `instance`, `properties`, and `context`
- if a `shared_keys` is `secure`, it is never available in the elements, only in server-side actions.
