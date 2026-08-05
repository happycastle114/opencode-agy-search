#!/usr/bin/env bash
set -euo pipefail

resolve_live_api_key_for_provider() {
  if [[ "$#" -ne 3 ]]; then
    printf 'usage: %s <provider> <explicit-live-api-key> <ambient-openai-api-key>\n' "${FUNCNAME[0]}" >&2
    return 64
  fi

  local provider=$1
  local explicit_live_api_key=$2
  local ambient_openai_api_key=$3

  case "$provider" in
    openai)
      if [[ -n "$explicit_live_api_key" ]]; then
        printf '%s' "$explicit_live_api_key"
      else
        printf '%s' "$ambient_openai_api_key"
      fi
      ;;
    *)
      # Provider-specific auth stores (for example opencode-go) must not
      # inherit an unrelated OPENAI_API_KEY from the caller's shell. Reject a
      # generic explicit key too, because this harness can only transport it as
      # OPENAI_API_KEY and cannot safely infer another provider's key contract.
      if [[ -n "$explicit_live_api_key" ]]; then
        printf 'OPENCODE_LIVE_API_KEY is supported only for the openai provider\n' >&2
        return 64
      fi
      ;;
  esac
}

link_opencode_auth_for_provider() {
  if [[ "$#" -ne 4 ]]; then
    printf 'usage: %s <provider> <live-api-key> <auth-file> <auth-destination>\n' "${FUNCNAME[0]}" >&2
    return 64
  fi

  local provider=$1
  local live_api_key=$2
  local auth_file=$3
  local auth_destination=$4

  if [[ ! -f "$auth_file" ]]; then
    return 0
  fi

  case "$provider" in
    opencode-go)
      # OpenCode's provider auth is stored in auth.json. Keep it available
      # even when the host has an unrelated API key in its environment.
      ;;
    *)
      if [[ -n "$live_api_key" ]]; then
        return 0
      fi
      ;;
  esac

  ln -s "$auth_file" "$auth_destination"
}
