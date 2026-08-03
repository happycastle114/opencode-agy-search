---
name: agy-search
description: Use the agy-search CLI for source-backed live web search, URL extraction, site mapping, bounded crawling, and multi-source research through Google Antigravity. Trigger when a task needs current web facts, primary sources, content from known URLs, documentation discovery, website analysis, comparisons, literature or market research, or a cited report without a separate search API key.
---

# Agy Search

Use the smallest operation that can answer the task, preserve returned URLs, and
escalate only when the evidence is insufficient.

## Preflight

Run this before the first research command in a task:

```bash
command -v agy-search
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
- Prefer primary sources and cross-check consequential or time-sensitive claims.
- State uncertainty when sources disagree or the bounded result is thin.
- Never cite the CLI, a local `.agy-search/` path, or an unreturned URL.

Read [references/commands.md](references/commands.md) for flags, response shapes,
and stable failure handling.
