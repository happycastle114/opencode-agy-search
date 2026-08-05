#!/usr/bin/env bash
set -euo pipefail

link_opencode_auth_without_env_key() {
  if [[ "$#" -ne 3 ]]; then
    printf 'usage: %s <live-api-key> <auth-file> <auth-destination>\n' "${FUNCNAME[0]}" >&2
    return 64
  fi

  local live_api_key=$1
  local auth_file=$2
  local auth_destination=$3

  if [[ -n "$live_api_key" || ! -f "$auth_file" ]]; then
    return 0
  fi

  ln -s "$auth_file" "$auth_destination"
}
