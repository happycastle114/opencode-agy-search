---
name: agy-search
description: Use the agy-search CLI for source-backed live web search, URL extraction, site mapping, bounded crawling, and multi-source research through Google Antigravity. Trigger when a task needs current web facts, primary sources, content from known URLs, documentation discovery, website analysis, comparisons, literature or market research, or a cited report without a separate search API key.
---

# Agy Search

Use the smallest operation that can answer the task, preserve returned URLs, and
escalate only when the evidence is insufficient.

## Preflight

Run this once before the first research command in the current agent session.
Do not repeat it for every query after it succeeds:

```bash
command -v agy-search
agy --version
agy-search status
```

If `agy-search` is unavailable, stop and report that installation is required.
When installation is in scope, use the release installer documented by the
project:

```bash
curl --proto '=https' --tlsv1.2 -LsSf \
  https://github.com/happycastle114/agy-search/releases/latest/download/agy-search-installer.sh | sh
```

Do not silently switch providers. After installation, repeat both preflight
commands. Run `agy-search models` before pinning a model; never invent or cache
a model slug.

The supported Antigravity floor is 1.1.10. If the user explicitly asks to
update a release-installer copy of `agy-search`, rerun its release installer and
then repeat preflight:

```bash
curl --proto '=https' --tlsv1.2 -LsSf \
  https://github.com/happycastle114/agy-search/releases/latest/download/agy-search-installer.sh \
  | sh
agy-search --version
agy-search status
```

The installer verifies the selected application archive and installs no second
updater executable. Never update either `agy-search` or `agy` implicitly.
Antigravity manages its own background updates during regular runs.

## Choose and escalate

| Need | Command |
|---|---|
| Quick facts or candidate sources | `agy-search search "query"` |
| Full content from known URLs | `agy-search extract https://example.com/page` |
| Discover relevant site URLs | `agy-search map https://example.com` |
| Read a bounded set of site pages | `agy-search crawl https://example.com` |
| Compare or synthesize sources | `agy-search research "question"` |

Escalate Search → Extract → Map → Crawl → Research only as needed. Map before
crawl when paths are unknown. Do not emulate Tavily-only concepts:
`agy-search research` is one-shot, with no request ID, polling, API key, credit
model, or exhaustive-crawl promise.

Fast default: run one `agy-search search "query" -n 3` and answer immediately
when its primary-source snippets directly support the claims. The CLI already
uses low effort by default. Do not extract or research merely to improve prose;
escalate only when snippets are insufficient, the user requests comparison or
deep synthesis, sources conflict, or the task is consequential/high-stakes.
Use `--effort medium` or `--effort high` only for that deliberate escalation.

## Save context

Use stdin `-` for generated or multiline queries. Save large output under the
task-local `.agy-search/` directory and inspect only needed fields:

```bash
printf '%s\n' "$QUERY" | agy-search search - -o .agy-search/search.json
agy-search extract https://example.com/page -o .agy-search/extract.json
agy-search map https://example.com -o .agy-search/map.json
agy-search crawl https://example.com --limit 20 -o .agy-search/crawl.json
agy-search research "$QUESTION" -o .agy-search/research.json
```

Prefer `jq` or targeted reads over loading an entire crawl into context. Keep
artifacts until the answer is complete so provenance can be checked.

## Validate evidence

- Require exit code 0 and the response `object` matching the command.
- Cite only returned `http://` or `https://` URLs that directly support a claim.
- For research, require every cited URL to appear in `sources`.
- Interpret `date` only as an explicit publication/release date and
  `last_updated` only as an explicit modification/update date; `null` means the
  structured result did not supply that metadata.
- Prefer primary sources and cross-check consequential or time-sensitive claims.
- State uncertainty when sources disagree or the bounded result is thin.
- Never cite the CLI, a local `.agy-search/` path, or an unreturned URL.

Read [references/commands.md](references/commands.md) for flags, response shapes,
and stable failure handling.
