#!/usr/bin/env bash
set -euo pipefail

opencode_bin=${OPENCODE_BIN:-}
agy_executable=${AGY_REAL_EXECUTABLE:-}
live_model=${OPENCODE_LIVE_MODEL:-}
agy_model=${AGY_LIVE_MODEL:-}

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
if ! command -v agy-search >/dev/null; then
  printf 'agy-search must be installed on PATH\n' >&2
  exit 2
fi
agy-search --agy-path "$agy_executable" models | \
  jq -e --arg model "$agy_model" '.models | index($model) != null' >/dev/null

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

mkdir -p "$e2e_root/package" "$e2e_root/workspace/.opencode/plugins"
npm pack --json --pack-destination "$e2e_root/package" >/dev/null
plugin_tarball=$(find "$e2e_root/package" -maxdepth 1 -type f -name '*.tgz')
tar -xzf "$plugin_tarball" -C "$e2e_root/package"
ln -s "$e2e_root/package/package/index.ts" "$e2e_root/workspace/.opencode/plugins/agy-search.ts"

(
  cd "$e2e_root/workspace"
  prompt=$(printf '%s' \
    "Use the agy-search skill. Run agy-search status. Then run exactly: agy-search --model $agy_model --effort low search 'Google Antigravity CLI 1.1.10 site:antigravity.google/changelog' -n 2 -o .agy-search/live-search.json. Do not mask its exit code. If it returns exit 6, retry once with the narrower query 'Antigravity 1.1.10 changelog'. Read the successful file and finish with the exact marker OPENCODE_AGY_SEARCH_LIVE_OK.")
  AGY_SEARCH_AGY_PATH="$agy_executable" CI=1 NO_COLOR=1 TERM=dumb \
    "$opencode_bin" run --model "$live_model" --format json \
    "$prompt" \
    >"$e2e_root/opencode.jsonl" 2>"$e2e_root/opencode.stderr"
)

result_path="$e2e_root/workspace/.agy-search/live-search.json"
[[ -s "$result_path" ]]
grep -F 'OPENCODE_AGY_SEARCH_LIVE_OK' "$e2e_root/opencode.jsonl" >/dev/null
grep -F 'agy-search' "$e2e_root/opencode.jsonl" >/dev/null
jq -e '.object == "search" and (.results | length > 0) and all(.results[]; (.url | startswith("http")))' \
  "$result_path" >/dev/null

printf '{"opencode_version":"%s","packed_plugin_loaded":true,"skill_invoked":true,"real_search_valid":true}\n' \
  "$("$opencode_bin" --version)"
