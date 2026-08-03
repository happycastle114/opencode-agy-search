# agy-search dependency rule

Before using the `agy-search` skill, verify `agy-search --version` reports 0.2.0
or newer, then run both `command -v agy-search` and `agy-search status`. If any
check fails, explain the missing prerequisite and stop.
Do not install packages, sign into Google Antigravity, change OpenCode config, or
switch search providers unless the user explicitly asks.

When the user explicitly asks to install the dependency, use:

```bash
curl --proto '=https' --tlsv1.2 -LsSf \
  https://github.com/happycastle114/agy-search/releases/latest/download/agy-search-installer.sh | sh
```

Use only model slugs returned by `agy-search models`. Global `--model`,
`--effort`, `--timeout`, and `--agy-path` options may appear before or after the
subcommand. Preserve JSON stdout for machine use and diagnostics on stderr.
