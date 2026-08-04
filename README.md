# @happycastle114/opencode-agy-search

Thin OpenCode plugin for the standalone
[`agy-search`](https://github.com/happycastle114/agy-search) CLI. It registers a
source-backed research skill and forwards the one documented Antigravity
executable override. The Rust CLI remains the sole owner of process execution,
schemas, provenance checks, JSON output, and exit codes.

## Requirements

- OpenCode 1.18.11
- `agy-search` 0.2.2 on `PATH`
- Google Antigravity CLI 1.1.10 or newer, signed in with web tools available

```bash
curl --proto '=https' --tlsv1.2 -LsSf \
  https://github.com/happycastle114/agy-search/releases/latest/download/agy-search-installer.sh | sh
agy-search --version
agy-search status
```

The plugin does not install dependencies or automate Google authentication.
To update a release-installer copy of the CLI, rerun its checksum-verifying
one-liner only when the user explicitly asks for that mutation.

## Install

Install the public GitHub Release artifact into OpenCode's documented global
plugin directory:

```bash
sh -c 'p=$(mktemp "${TMPDIR:-/tmp}/opencode-agy-search.XXXXXX") || exit 1; trap '\''rm -f "$p"'\'' EXIT; curl --proto "=https" --tlsv1.2 -LsSf https://github.com/happycastle114/opencode-agy-search/releases/latest/download/opencode-agy-search-installer.sh -o "$p" && sh "$p"'
```

The installer downloads a version-pinned npm tarball and checksum from the
GitHub release, verifies SHA-256, rejects archive links and unsafe paths, keeps
versioned payloads under the XDG data directory, and safely switches one
TypeScript plugin into
`~/.config/opencode/plugins/`. It does not store tokens or edit `.npmrc` or
`opencode.json`. Rerun the same one-liner to update.

Restart OpenCode, then verify both plugin surfaces:

```bash
opencode debug config
opencode debug skill
```

The `agy-search` skill should be listed. Ask OpenCode to use it for live search,
known-URL extraction, site mapping, bounded crawling, or cited research.

## GitHub Packages

The same JavaScript package is published publicly as
`@happycastle114/opencode-agy-search@0.3.0` at GitHub Packages. GitHub's npm
registry requires a classic personal access token with `read:packages` even for
public packages, so this is the authenticated package-manager channel rather
than the public one-liner channel.

The release workflow verifies the published version, tarball integrity, and
`public` package visibility through GitHub before it creates the GitHub Release.

Map the scope to GitHub Packages in npm configuration and provide the token only
through the environment:

```ini
@happycastle114:registry=https://npm.pkg.github.com
//npm.pkg.github.com/:_authToken=${GITHUB_TOKEN}
```

Never commit a token-bearing `.npmrc`. The release installer above is preferred
for normal OpenCode use because it needs no registry credential.

If an older npm package entry is still present in `opencode.json`, remove it
before using the local installer. OpenCode loads npm and local plugins as
separate sources, so keeping both would run both copies.

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
