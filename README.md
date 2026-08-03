# @happycastle/opencode-agy-search

Thin OpenCode plugin for the standalone
[`agy-search`](https://github.com/happycastle114/agy-search) CLI. It registers a
source-backed research skill and forwards the one documented Antigravity
executable override. The Rust CLI remains the sole owner of process execution,
schemas, provenance checks, JSON output, and exit codes.

## Requirements

- OpenCode 1.18.11
- `agy-search` 0.2.0 on `PATH`
- Google Antigravity CLI 1.1.8 or newer, signed in with web tools available

```bash
curl --proto '=https' --tlsv1.2 -LsSf \
  https://github.com/happycastle114/agy-search/releases/latest/download/agy-search-installer.sh | sh
agy-search --version
agy-search status
```

The plugin does not install dependencies or automate Google authentication.

## Install

Add the version-pinned npm package to `opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["@happycastle/opencode-agy-search@0.2.0"]
}
```

Restart OpenCode, then verify both plugin configuration surfaces:

```bash
opencode debug config
opencode debug skill
```

The `agy-search` skill should be listed. Ask OpenCode to use it for live search,
known-URL extraction, site mapping, bounded crawling, or cited research.

## Executable override

Set `AGY_SEARCH_AGY_PATH` when `agy` is not discoverable on the shell `PATH`:

```bash
export AGY_SEARCH_AGY_PATH=/absolute/path/to/agy
opencode
```

Only that variable is forwarded by the `shell.env` hook. Credentials and other
host environment values are not copied by this plugin.

## Development

```bash
bun install --frozen-lockfile
bun test
bun run typecheck
npm pack --dry-run

OPENCODE_BIN=/opt/homebrew/bin/opencode bun run test:e2e

OPENCODE_BIN=/opt/homebrew/bin/opencode \
AGY_REAL_EXECUTABLE=/absolute/path/to/agy \
OPENCODE_LIVE_MODEL=provider/model \
AGY_LIVE_MODEL=gemini-3.6-flash-low \
bun run test:e2e:live
```

The deterministic E2E packs and extracts the npm artifact, loads it through an
isolated OpenCode config, and verifies the injected instruction and skill paths.
The opt-in live E2E additionally proves OpenCode → packed plugin → skill →
installed `agy-search` → authenticated `agy` with a real search response.
