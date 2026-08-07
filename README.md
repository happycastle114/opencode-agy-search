# @happycastle114/opencode-agy-search

Thin OpenCode plugin for the standalone
[`agy-search`](https://github.com/happycastle114/agy-search) CLI. It registers a
source-backed research skill and forwards the one documented Antigravity
executable override plus its optional curl transport override. The Rust CLI
remains the sole owner of process execution,
schemas, provenance checks, JSON output, and exit codes.

## Requirements

- OpenCode 1.18.11
- `agy-search` 0.2.8 on `PATH`
- `curl` for bounded grounding-link resolution and opt-in temporal source checks
- Google Antigravity CLI 1.1.10 or newer, signed in with web tools available

Before the first search in an agent session, run the cheap local preflight:

```bash
command -v agy-search
command -v agy
command -v curl
agy-search --version
agy --version
```

Ordinary searches must omit both `agy-search models` and `--model`. CLI 0.2.8
performs its own bounded advisory catalog lookup and prefers the exact
`gemini-3.6-flash-low` slug when present; that internal preference is not a
caller model pin. The core enforces the same Antigravity floor before content
and `status`.

For installation/update verification, then run:

```bash
curl --proto '=https' --tlsv1.2 -LsSf \
  https://github.com/happycastle114/agy-search/releases/latest/download/agy-search-installer.sh | sh
agy-search --version
agy --version
agy-search status
```

The plugin does not install dependencies or automate Google authentication.
To update a release-installer copy of the CLI, rerun its checksum-verifying
one-liner only when the user explicitly asks for that mutation. Its checksum is
a same-release integrity check, not an independent signature or provenance
attestation.

## Install

Install the public GitHub Release artifact into OpenCode's documented global
plugin directory:

```bash
sh -c 'p=$(mktemp "${TMPDIR:-/tmp}/opencode-agy-search.XXXXXX") || exit 1; trap '\''rm -f "$p"'\'' EXIT; curl --disable --proto "=https" --proto-redir "=https" --tlsv1.2 --noproxy "*" --cookie "" --no-netrc -LsSf https://github.com/happycastle114/opencode-agy-search/releases/latest/download/opencode-agy-search-installer.sh -o "$p" && sh "$p"'
```

The installer downloads a version-pinned npm tarball and checksum from the same
GitHub release, verifies SHA-256, rejects archive links and unsafe paths, keeps
versioned payloads under the XDG data directory, and safely switches one
TypeScript plugin into `~/.config/opencode/plugins/`. The checksum checks
integrity against that release asset pair; it is not an independent signature
or separately authenticated provenance proof. It does not store tokens or edit
`.npmrc` or `opencode.json`. Rerun the same one-liner to update.

Restart OpenCode, then verify both plugin surfaces:

```bash
opencode debug config
opencode debug skill
```

The `agy-search` skill should be listed. Ask OpenCode to use it for live search,
known-URL extraction, site mapping, bounded crawling, or cited research.

## Research routing

The bundled skill chooses depth before its first content call. A stable,
low-stakes fact starts with one low-effort `search -n 3`; current versions,
explicit dates, and several sections of one canonical source use a verified
`search -n 3`; independent-source synthesis starts with `research`; high-stakes or
conflicting evidence uses high-effort research. The commands are bounded at 45
seconds for Quick, 75 for Verified, 120 for Synthesis, and 180 for Deep unless
the user explicitly requests another timeout. An exact latest tuple or
as-of comparison adds the typed temporal verifier with 1-8 exact `--scope`
values and 1-8 canonical HTTPS `--source-url` values. One scope verifies only
that tuple and requires `--as-of`; 2-8 scopes additionally select one unique
latest member. The cutoff is inclusive, temporal-only, and never future;
standard mode rejects it. If the inventory is unknown,
the skill discovers a proposed set first and never calls a model-selected subset
globally exhaustive. Requests for each source's current release or tradeoffs
remain standard Research, not a global-winner temporal comparison.

Depth is lowest-sufficient: Quick is the default for one stable factual lookup,
Verified covers factual/current claims needing canonical evidence, Synthesis is
for real comparisons across independent sources, and Deep is reserved for broad,
high-stakes, exhaustive-ambiguity, or conflicting work. Quick/Verified stay at
low effort with small search budgets; Synthesis and Deep use bounded research
budgets. The skill de-escalates when a higher trigger does not apply and never
calls `research` merely because the request says "research". It verifies the
selected response end to end before reporting material claims.

Ordinary preflight runs `command -v agy-search`, `command -v agy`,
`command -v curl`, `agy-search --version`, and `agy --version` only. The core
rejects a bare semantic version below 1.1.10 before content or `status`, without
model discovery. It does not run `status` or `models`, and it does not repeat an
identical broad query. `status` is reserved for diagnosis/install verification,
while `models` runs once only for an explicit model pin. Temporal search may use one bounded
all-or-nothing recovery across the caller-owned scopes; temporal research
remains one-shot. Both fail closed unless every declared scope/value/date tuple
binds to a safely fetched declared source body. Temporal results require
`last_updated: null` because the current verifier binds publication dates, not
modification dates. In Standard Search, `date` is optional; a valid date that
cannot bind to evidence is emitted as `null`, while malformed dates remain
invalid. Research and temporal dates remain strict. Standard searches add no
body fetch, but every result and audit URL receives a bounded, header-only,
DNS-pinned terminal HTTPS check. Google transports are resolved and dead,
unsafe, regional Google search, or cache rows are removed with their audit rows.
Standard Search may use up to two quality-model recoveries (three total
attempts) only when no publishable result survives; every attempt shares the
original command deadline. A
cutoff permits strong caller-owned first
rows to replace a wrong model value/date only when every declared scope is at or
before the cutoff; otherwise Search performs the complete scoped fallback.
Without a cutoff, primary-value anchoring remains.

For Search and Research, `--domain` is the canonical caller-owned domain-tree allowlist
and `--source-url` is the canonical exact-URL allowlist. Standard exact URLs
restrict membership only and do not fetch source bodies; temporal exact URLs are
fetched/verified and dominate same-domain paths. Preferences such as `prefer`,
`prioritize`, `favor`, or a primary-source preference change query prose and
result ranking only; they never create an allowlist. The skill passes
`--domain` or `--source-url` only for an explicit exclusive source constraint
or an explicitly supplied trusted set. For hard caller source constraints such
as `only official`, `only first-party`, and `only project-maintained`, it MUST
pass explicitly trusted domains/URLs, but does not infer ownership from a domain
or name because flags prove membership only. If the exact trust set is
unavailable, it stops and reports mechanical enforcement is impossible, or does
only user-permitted discovery as unverified candidates. Antigravity cannot
guarantee that no third-party snippet was ever viewed. Conclusions beyond
returned source text are labeled `Inference:`.
Ordinary work omits both `agy-search models` and `--model`; CLI 0.2.8 performs
its bounded advisory catalog lookup internally and prefers exact
`gemini-3.6-flash-low` when present. An explicit returned model slug ending
`-low`, `-medium`, or `-high` must use matching `--effort`.

## GitHub Packages

The same JavaScript package is published publicly as
`@happycastle114/opencode-agy-search@0.3.9` at GitHub Packages. GitHub's npm
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

## Executable overrides

Set `AGY_SEARCH_AGY_PATH` when `agy` is not discoverable on the shell `PATH`.
Set `AGY_SEARCH_CURL_PATH` only when a non-default curl is required:

```bash
export AGY_SEARCH_AGY_PATH=/absolute/path/to/agy
export AGY_SEARCH_CURL_PATH=/absolute/path/to/curl
opencode
```

Only those two executable overrides are forwarded by the `shell.env` hook.
Credentials and other host environment values are not copied by this plugin.

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

`bun run test:e2e:routing:live` is a separate live-model routing test. It runs
four fresh OpenCode sessions against a deterministic fixture `agy-search` CLI,
fails on fixture, JSON, tool, or agent errors, and proves Quick/Verified/
Synthesis/Deep command selection. It is not web-search or source-accuracy proof;
the real CLI live E2E and its source assertions own that claim.
`bun run test:routing:fixture` independently verifies the fixture's Synthesis
and Deep extract follow-ups plus its nonzero-exit ledger.
