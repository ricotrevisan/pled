# Commands

All scripts are in the `scripts/` directory relative to the skill root.

## Init — scaffold a new plugin project

```bash
bash scripts/init.sh <bubble-plugin-url-or-id>
```

Accepts a Bubble plugin editor URL or a raw plugin ID. Extracts the ID, writes `.plugin_id`, and scaffolds the project structure.

## Pull — fetch plugin from Bubble and decode to local files

```bash
bash scripts/pull.sh
```

## Push — encode local files and upload to Bubble

```bash
bash scripts/push.sh          # with remote change detection
bash scripts/push.sh --force   # skip remote check
```

## Encode — compile src/ to dist/plugin.json without uploading

```bash
bash scripts/encode.sh
```

## Upload — upload a file to Bubble CDN

```bash
bash scripts/upload.sh path/to/file.js
```

## Watch — auto-push on file changes

```bash
bash scripts/watch.sh
```

## Check Remote — detect remote changes without pushing

```bash
bash scripts/check-remote.sh
```

## Status — show environment and sync status

```bash
bash scripts/status.sh
```
