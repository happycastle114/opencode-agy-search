# agy-search dependency rule

Before using the `agy-search` skill, verify both `command -v agy-search` and
`agy-search status`. If either fails, explain the missing prerequisite and stop.
Do not install packages, sign into Google Antigravity, change OpenCode config, or
switch search providers unless the user explicitly asks.

Use only model slugs returned by `agy-search models`. Put global `--model`,
`--effort`, `--timeout`, and `--agy-path` options before the subcommand. Preserve
JSON stdout for machine use and keep diagnostics on stderr.
