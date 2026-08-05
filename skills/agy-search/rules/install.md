# agy-search dependency rule

Before the first `agy-search` command in an agent session, run only
`command -v agy-search`, `command -v agy`, `command -v curl`,
`agy-search --version`, and `agy --version`. Require agy-search 0.2.4 or newer.
If a check fails, explain the missing prerequisite and stop. Do not run
`agy-search status` or `agy-search models` as ordinary preflight; they start
downstream discovery and make simple searches slower.
Do not install packages, sign into Google Antigravity, change OpenCode config, or
switch search providers unless the user explicitly asks.

When the user explicitly asks to install the dependency, use:

```bash
curl --proto '=https' --tlsv1.2 -LsSf \
  https://github.com/happycastle114/agy-search/releases/latest/download/agy-search-installer.sh | sh
```

The core accepts only bare `X.Y.Z` output from `agy --version` and rejects a
bare semantic version below 1.1.10 before content or `status`, without model
discovery. When the user explicitly requests a model pin, run `agy-search models` once and
use only a returned slug. Otherwise omit `--model`. Run `agy-search status` only
to diagnose availability or verify an install/update. Antigravity 1.1.10 or
newer is required. A pinned slug ending `-low`, `-medium`, or `-high` must use
the matching `--effort`; a mismatch is invalid. Global `--model`, `--effort`,
`--timeout`, and `--agy-path` options may appear before or after the subcommand.
`--as-of YYYY-MM-DD` belongs only to temporal Search or Research, is inclusive,
and must never be future. Preserve JSON stdout for machine use and diagnostics
on stderr.

When the user explicitly asks to update a release-installer copy, rerun the
checksum-verifying release installer, then verify `agy-search --version` and
`agy --version` and `agy-search status`. Its same-release checksum verifies
integrity, not independent signature or provenance. Never trigger updates as a preflight or background action;
Antigravity manages its own background updates.
