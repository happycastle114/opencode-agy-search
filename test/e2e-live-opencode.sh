#!/usr/bin/env bash
set -euo pipefail

opencode_bin=${OPENCODE_BIN:-}
agy_executable=${AGY_REAL_EXECUTABLE:-}
live_model=${OPENCODE_LIVE_MODEL:-}
agy_model=${AGY_LIVE_MODEL:-}
live_home=${HOME:?}
auth_file=${OPENCODE_AUTH_FILE:-$live_home/.local/share/opencode/auth.json}

if [[ -z "$opencode_bin" || ! -x "$opencode_bin" ]]; then
  printf 'OPENCODE_BIN must identify an executable\n' >&2
  exit 2
fi
if [[ -z "$agy_executable" || ! -x "$agy_executable" ]]; then
  printf 'AGY_REAL_EXECUTABLE must identify an executable\n' >&2
  exit 2
fi
if [[ -z "$live_model" ]]; then
  printf 'OPENCODE_LIVE_MODEL must identify an authenticated OpenCode model\n' >&2
  exit 2
fi
if [[ -z "$agy_model" ]]; then
  printf 'AGY_LIVE_MODEL must identify a slug returned by agy-search models\n' >&2
  exit 2
fi
if [[ ! -f "$auth_file" ]]; then
  printf 'OPENCODE_AUTH_FILE must identify an OpenCode auth file\n' >&2
  exit 2
fi
if ! command -v agy-search >/dev/null; then
  printf 'agy-search must be installed on PATH\n' >&2
  exit 2
fi
if ! command -v agy >/dev/null; then
  printf 'agy must be installed on PATH\n' >&2
  exit 2
fi
if ! command -v curl >/dev/null; then
  printf 'curl must be installed on PATH\n' >&2
  exit 2
fi
agy-search --version >/dev/null
agy --version >/dev/null

temp_base=$(cd "${TMPDIR:-/tmp}" && pwd -P)
e2e_root=$(mktemp -d "$temp_base/opencode-agy-search-live.XXXXXX")
touch "$e2e_root/.opencode-agy-search-live-owned"

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if [[ "$status" -ne 0 && -f "$e2e_root/opencode.stderr" ]]; then
    printf 'OpenCode live E2E stderr:\n' >&2
    sed -n '1,120p' "$e2e_root/opencode.stderr" >&2
  fi
  if [[ "$status" -ne 0 && -f "$e2e_root/opencode.jsonl" ]]; then
    printf 'OpenCode live E2E tail:\n' >&2
    tail -n 40 "$e2e_root/opencode.jsonl" >&2
  fi
  case "$e2e_root" in
    "$temp_base"/opencode-agy-search-live.*)
      if [[ -f "$e2e_root/.opencode-agy-search-live-owned" ]]; then
        find "$e2e_root" -depth -delete
      else
        printf 'cleanup marker missing; refusing deletion\n' >&2
        status=1
      fi
      ;;
    *)
      printf 'cleanup prefix mismatch; refusing deletion\n' >&2
      status=1
      ;;
  esac
  exit "$status"
}
trap cleanup EXIT INT TERM

mkdir -p \
  "$e2e_root/bin" \
  "$e2e_root/home" \
  "$e2e_root/package" \
  "$e2e_root/tmp" \
  "$e2e_root/workspace/.opencode/plugins" \
  "$e2e_root/zdot" \
  "$e2e_root/xdg/cache" \
  "$e2e_root/xdg/config" \
  "$e2e_root/xdg/data/opencode" \
  "$e2e_root/xdg/state"
npm pack --json --pack-destination "$e2e_root/package" >/dev/null
plugin_tarball=$(find "$e2e_root/package" -maxdepth 1 -type f -name '*.tgz')
tar -xzf "$plugin_tarball" -C "$e2e_root/package"
plugin_root="$e2e_root/package/package"
plugin_entry="$plugin_root/index.ts"
skill_directory="$plugin_root/skills/agy-search"
jq -e '.version == "0.3.10" and .agySearch.minimumCliVersion == "0.2.9"' \
  "$plugin_root/package.json" >/dev/null
[[ -f "$plugin_entry" && -f "$skill_directory/SKILL.md" ]]
ln -s "$plugin_entry" "$e2e_root/workspace/.opencode/plugins/agy-search.ts"
ln -s "$auth_file" "$e2e_root/xdg/data/opencode/auth.json"

agy_search_directory=$(dirname "$(command -v agy-search)")
agy_wrapper="$e2e_root/bin/agy"
printf '#!/bin/sh\nHOME=%q\nexport HOME\nexec %q "$@"\n' \
  "$live_home" "$agy_executable" >"$agy_wrapper"
chmod 0500 "$agy_wrapper"
isolated_env=(
  "PATH=$e2e_root/bin:$agy_search_directory:$(dirname "$opencode_bin"):/usr/bin:/bin"
  "HOME=$e2e_root/home"
  "XDG_CONFIG_HOME=$e2e_root/xdg/config"
  "XDG_DATA_HOME=$e2e_root/xdg/data"
  "XDG_CACHE_HOME=$e2e_root/xdg/cache"
  "XDG_STATE_HOME=$e2e_root/xdg/state"
  "ZDOTDIR=$e2e_root/zdot"
  "TMPDIR=$e2e_root/tmp"
  "AGY_SEARCH_AGY_PATH=$agy_wrapper"
  "CI=1"
  "NO_COLOR=1"
  "TERM=dumb"
)

(
  cd "$e2e_root/workspace"
  prompt=$(printf '%s' \
    "Use the agy-search skill. For the cheap preflight, run command -v agy-search, command -v agy, command -v curl, agy-search --version, and agy --version only. Then run exactly: agy-search --model $agy_model --effort low search 'IANA example domain' -n 1 -o .agy-search/live-search.json. Do not mask its exit code. Do not run status or models, and do not repeat an identical broad query. Read the successful file and finish with the exact marker OPENCODE_AGY_SEARCH_LIVE_OK.")
  env -i "${isolated_env[@]}" \
    "$opencode_bin" run --model "$live_model" --format json \
    "$prompt" \
    >"$e2e_root/opencode.jsonl" 2>"$e2e_root/opencode.stderr"
)

result_path="$e2e_root/workspace/.agy-search/live-search.json"
[[ -s "$result_path" ]]
grep -F 'OPENCODE_AGY_SEARCH_LIVE_OK' "$e2e_root/opencode.jsonl" >/dev/null
grep -F 'agy-search' "$e2e_root/opencode.jsonl" >/dev/null
jq -e --arg skill_directory "$skill_directory" '
  select(
    .type == "tool_use"
      and .part.tool == "skill"
      and .part.state.status == "completed"
      and .part.state.metadata.name == "agy-search"
      and .part.state.metadata.dir == $skill_directory
  )
' "$e2e_root/opencode.jsonl" >/dev/null
jq -e '
  def terminal_public_https:
    capture("^https://(?<host>[^/:?#]+)(?<path>/[^?#]*)?") as $url
    | ($url.host | ascii_downcase) as $host
    | ($url.path // "/") as $path
    | $host != "vertexaisearch.cloud.google.com"
      and (((($host == "google.com") or ($host | endswith(".google.com")))
        and (($path == "/search") or ($path == "/url"))) | not);
  [.results[]?.url, .sources[]?.url, .evidence_audit?.candidates[]?.url] as $public_urls
  | .object == "search"
    and ($public_urls | length > 0)
    and ($public_urls | all(type == "string" and terminal_public_https))
' \
  "$result_path" >/dev/null

printf '{"opencode_version":"%s","packed_plugin_loaded":true,"skill_invoked":true,"real_search_valid":true}\n' \
  "$("$opencode_bin" --version)"
