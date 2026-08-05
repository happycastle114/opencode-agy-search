#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd -P)
auth_helper="$repo_root/test/routing-live-auth.sh"
temp_base=$(cd "${TMPDIR:-/tmp}" && pwd -P)
test_root=$(mktemp -d "$temp_base/opencode-agy-routing-auth.XXXXXX")
touch "$test_root/.opencode-agy-routing-auth-owned"

cleanup() {
  local result_code=$?
  trap - EXIT INT TERM
  case "$test_root" in
    "$temp_base"/opencode-agy-routing-auth.*)
      if [[ -f "$test_root/.opencode-agy-routing-auth-owned" ]]; then
        find "$test_root" -depth -delete
      else
        printf 'cleanup marker missing; refusing deletion\n' >&2
        result_code=1
      fi
      ;;
    *)
      printf 'cleanup prefix mismatch; refusing deletion\n' >&2
      result_code=1
      ;;
  esac
  exit "$result_code"
}
trap cleanup EXIT INT TERM

# shellcheck source=routing-live-auth.sh
[[ -f "$auth_helper" ]] || {
  printf 'routing live auth helper is unavailable: %s\n' "$auth_helper" >&2
  exit 66
}
source "$auth_helper"

auth_source="$test_root/auth.json"
printf '%s\n' '{}' >"$auth_source"

fallback_destination="$test_root/fallback/auth.json"
mkdir -p "$(dirname "$fallback_destination")"
link_opencode_auth_without_env_key "" "$auth_source" "$fallback_destination"
[[ -L "$fallback_destination" ]]
[[ "$(readlink "$fallback_destination")" == "$auth_source" ]]
printf '%s\n' 'routing live auth precedence observed: fallback-auth-link'

explicit_key_destination="$test_root/explicit-key/auth.json"
mkdir -p "$(dirname "$explicit_key_destination")"
link_opencode_auth_without_env_key "present" "$auth_source" "$explicit_key_destination"
[[ ! -e "$explicit_key_destination" ]]
[[ ! -L "$explicit_key_destination" ]]
printf '%s\n' 'routing live auth precedence observed: explicit-key-omits-auth-file'

printf '%s\n' 'routing live auth precedence contract: PASS'
