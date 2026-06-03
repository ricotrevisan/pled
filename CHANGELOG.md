# Changelog

## v0.0.29-beta

### Fixed
- Report Bubble `401 Unauthorized` upload failures with actionable guidance for
  refreshing `BUBBLE_COOKIE` and verifying plugin edit permissions
- Stop `pled status` from claiming the cookie is valid when the public plugin
  fetch endpoint succeeds; it now reports remote reachability instead

## v0.0.28-beta

### Added
- Per-command help: `pled <command> --help` and `pled help <command>` now show
  detailed usage, options, and examples for each command
- Help text for all 8 commands: pull, push, encode, upload, watch, init,
  check-remote, status
- General help now mentions `pled help <command>` for more details
- Comprehensive tests for all help output and help flag routing

## v0.0.27-beta

- Add agent skill, improve docs, remove dependency on `direnv`

## v0.0.26-beta

- `pled init` now accepts a Bubble plugin URL or ID as argument (e.g.
  `pled init https://bubble.io/plugin_editor?id=1234x5678`)
- Add `.plugin_id` file support: replaces `.envrc`/`PLUGIN_ID` env var approach
- Add `PluginId` module for resolving plugin ID from `.plugin_id` file, env var,
  or Bubble URLs
- Add `status` command: shows environment, auth, and sync status
- Refactor `init` command to save plugin ID to `.plugin_id` instead of `.envrc`

## v0.0.25-beta

- Fixed DS file error, improved parsing

## v0.0.24-beta

- `pled watch` improvement when making changes directly on Bubble
- Improved README

## v0.0.23-beta

- Working version with various fixes

## v0.0.22-beta

- Improved LLM text, added Gemini file

## v0.0.21-beta

- Improved LLM text
