#!/usr/bin/env bash
set -euo pipefail

opencode_bin=${OPENCODE_BIN:-}

if [[ -z "$opencode_bin" || ! -x "$opencode_bin" ]]; then
  printf 'OPENCODE_BIN must identify an executable\n' >&2
  exit 2
fi
if [[ "$("$opencode_bin" --version)" != 1.18.11 ]]; then
  printf 'OpenCode 1.18.11 is required\n' >&2
  exit 3
fi

temp_base=$(cd "${TMPDIR:-/tmp}" && pwd -P)
e2e_root=$(mktemp -d "$temp_base/opencode-agy-search.XXXXXX")
touch "$e2e_root/.opencode-agy-search-owned"

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  case "$e2e_root" in
    "$temp_base"/opencode-agy-search.*)
      if [[ -f "$e2e_root/.opencode-agy-search-owned" ]]; then
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
  "$e2e_root/config" \
  "$e2e_root/home" \
  "$e2e_root/plugin" \
  "$e2e_root/tmp" \
  "$e2e_root/workspace" \
  "$e2e_root/xdg/cache" \
  "$e2e_root/xdg/config" \
  "$e2e_root/xdg/data" \
  "$e2e_root/xdg/state"

npm pack --json --pack-destination "$e2e_root/plugin" >/dev/null
plugin_tarball=$(find "$e2e_root/plugin" -maxdepth 1 -type f -name '*.tgz')
tar -xzf "$plugin_tarball" -C "$e2e_root/plugin"
plugin_entry="$e2e_root/plugin/package/index.ts"
skill_directory="$e2e_root/plugin/package/skills/agy-search"
[[ -f "$plugin_entry" ]]
[[ -f "$skill_directory/SKILL.md" ]]

plugin_url=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve().as_uri())' "$plugin_entry")
config_path="$e2e_root/config/opencode.json"
python3 - "$config_path" "$plugin_url" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(
    json.dumps({"$schema": "https://opencode.ai/config.json", "plugin": [sys.argv[2]]}),
    encoding="utf-8",
)
PY

isolated_path="$(dirname "$opencode_bin"):/opt/homebrew/bin:/usr/bin:/bin"
isolated_env=(
  "PATH=$isolated_path"
  "HOME=$e2e_root/home"
  "XDG_CONFIG_HOME=$e2e_root/xdg/config"
  "XDG_DATA_HOME=$e2e_root/xdg/data"
  "XDG_CACHE_HOME=$e2e_root/xdg/cache"
  "XDG_STATE_HOME=$e2e_root/xdg/state"
  "TMPDIR=$e2e_root/tmp"
  "OPENCODE_CONFIG=$config_path"
  "OPENCODE_CONFIG_DIR=$e2e_root/config"
  "AGY_SEARCH_AGY_PATH=/fixture/agy"
  "CI=1"
  "TERM=dumb"
  "NO_COLOR=1"
)

(
  cd "$e2e_root/workspace"
  env -i "${isolated_env[@]}" "$opencode_bin" debug config >"$e2e_root/resolved-config.json"
  env -i "${isolated_env[@]}" "$opencode_bin" debug skill >"$e2e_root/debug-skill.txt"
)

grep -F "$plugin_entry" "$e2e_root/resolved-config.json" >/dev/null
grep -F "$skill_directory/rules/install.md" "$e2e_root/resolved-config.json" >/dev/null
grep -F "$skill_directory" "$e2e_root/resolved-config.json" >/dev/null
grep -F 'agy-search' "$e2e_root/debug-skill.txt" >/dev/null

printf '{"opencode_version":"1.18.11","packed_plugin_loaded":true,"skill_discovered":true}\n'
