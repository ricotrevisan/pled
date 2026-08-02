# Changelog

## v0.1.1

### Fixed
- `pled watch` explains that the OS file watcher could not start instead of
  crashing with a `MatchError` (Linux hosts without `inotify-tools`)

## v0.1.0

First release out of beta. Pled no longer overwrites work silently. Every sync operation now compares
three sides — the baseline snapshot, your local `src/`, and the Bubble plugin —
and refuses anything that would discard changes you did not ask to discard.

### Added
- `Pled.Sync`: a three-way sync engine classifying the workspace as in sync,
  local ahead, remote ahead, diverged, or missing a baseline
- `pled status` and `pled check-remote` report that state and always name the
  exact next command to run
- `pled pull --wipe` to discard local changes explicitly
- `pled watch --interval <seconds>` to set the remote poll period (default 15s)

### Changed
- `pled watch` is now conflict-aware: it pushes local edits only while the
  remote is clean, pulls remote changes only while nothing local is unpushed,
  and pauses with a conflict banner when both sides moved — resuming on its own
  once you resolve it. It no longer force-pushes on every save.
- `pled push` refuses to upload when the remote moved since your last pull;
  `--force` states that intent explicitly
- `pled pull` refuses to overwrite unpushed local changes, and removes entities
  deleted or renamed in Bubble instead of leaving stale directories behind
- Watch reports network failures with exponential backoff and warns loudly when
  `BUBBLE_COOKIE` expires, instead of silently dying

### Fixed
- `pled pull` no longer crashes or corrupts the source tree on work-in-progress
  plugins with missing or malformed entities
- Action code sections without a body round-trip through pull/push unchanged
- Encoder validation issues are reported as errors in unattended contexts
  instead of blocking on a prompt

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
