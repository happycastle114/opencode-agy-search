# Command reference

```bash
agy-search [--agy-path PATH] [--model SLUG] [--effort low|medium|high] \
  [--timeout SECONDS] COMMAND

agy-search status [--json] [-o PATH]
agy-search models [--json] [-o PATH]
agy-search search QUERY [-n N] [--domain DOMAIN]... [--json] [-o PATH]
agy-search extract URL... [--query TEXT] [--json] [-o PATH]
agy-search map URL [--limit N] [--instructions TEXT] [--allow-external] [--json] [-o PATH]
agy-search crawl URL [--limit N] [--instructions TEXT] [--allow-external] [--json] [-o PATH]
agy-search research QUERY [--max-sources N] [--json] [-o PATH]
```

Content responses use `object` discriminators `search`, `extract`, `map`,
`crawl`, and `research`. Research includes `findings[].citations[]` and
`sources[].url`; every citation must occur in the returned sources.

| Exit | Meaning |
|---:|---|
| 0 | Success |
| 2 | Invalid input or output target |
| 3 | `agy` unavailable |
| 4 | Timeout |
| 5 | Downstream failure |
| 6 | Invalid or sourceless output |
| 7 | Unknown model; rediscover models |
