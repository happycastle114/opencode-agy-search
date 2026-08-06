#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd -P)
harness="$repo_root/test/e2e-routing-live-opencode.sh"
bun_bin=$(command -v bun)
bun_dir=$(dirname "$bun_bin")
npm_dir=$(dirname "$(command -v npm)")
jq_dir=$(dirname "$(command -v jq)")
perl_dir=$(dirname "$(command -v perl)")
python_dir=$(dirname "$(command -v python3)")
bash_dir=$(dirname "$(command -v bash)")
temp_base=$(cd "${TMPDIR:-/tmp}" && pwd -P)
test_root=$(mktemp -d "$temp_base/opencode-agy-routing-harness.XXXXXX")
touch "$test_root/.opencode-agy-routing-harness-owned"

cleanup() {
  local result_code=$?
  trap - EXIT INT TERM
  case "$test_root" in
    "$temp_base"/opencode-agy-routing-harness.*)
      if [[ -f "$test_root/.opencode-agy-routing-harness-owned" ]]; then
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

[[ -f "$harness" ]] || {
  printf 'routing live harness is unavailable: %s\n' "$harness" >&2
  exit 66
}

fake_opencode="$test_root/opencode"
cat >"$fake_opencode" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == --version ]]; then
  printf '1.18.11\n'
  exit 0
fi
if [[ "${1:-}" == debug ]]; then
  case "${2:-}" in
    config) printf '{}\n' ;;
    skill) printf 'agy-search\n' ;;
    *) exit 99 ;;
  esac
  exit 0
fi
if [[ "${1:-}" == run ]]; then
  sleep 10
  exit 99
fi
exit 99
SHIM
chmod +x "$fake_opencode"
printf '%s\n' '{}' >"$test_root/auth.json"

run_expect_failure() {
  local label=$1
  local expected_status=$2
  shift 2
  local output="$test_root/$label.output"
  local status=0

  set +e
  "$@" >"$output" 2>&1
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    printf '%s unexpectedly returned zero\n' "$label" >&2
    cat "$output" >&2
    return 1
  fi
  if [[ "$status" -ne "$expected_status" ]]; then
    printf '%s returned %s, expected %s\n' "$label" "$status" "$expected_status" >&2
    cat "$output" >&2
    return 1
  fi
  grep -F 'injected' "$output" >/dev/null
  printf '%s exit=%s\n' "$label" "$status"
}

run_expect_config_failure() {
  local label=$1
  local expected_status=$2
  local expected_message=$3
  shift 3
  local output="$test_root/$label.output"
  local status=0

  set +e
  "$@" >"$output" 2>&1
  status=$?
  set -e
  if [[ "$status" -ne "$expected_status" ]]; then
    printf '%s returned %s, expected %s\n' "$label" "$status" "$expected_status" >&2
    cat "$output" >&2
    return 1
  fi
  grep -F "$expected_message" "$output" >/dev/null
  printf '%s exit=%s\n' "$label" "$status"
}

run_expect_quick_timeout() {
  local output="$test_root/quick-timeout.output"
  local started_at
  local finished_at
  local status=0
  started_at=$(date +%s)
  set +e
  "$@" >"$output" 2>&1
  status=$?
  set -e
  finished_at=$(date +%s)
  if [[ "$status" -ne 124 ]]; then
    printf 'quick timeout returned %s, expected 124\n' "$status" >&2
    cat "$output" >&2
    return 1
  fi
  grep -F 'quick routing scenario hit 1 second hard deadline' "$output" >/dev/null
  [[ $((finished_at - started_at)) -lt 6 ]]
  local timing_file
  timing_file=$(find "$test_root/evidence" -path '*/quick-preference/timing.json' -type f | sort | tail -1)
  [[ -f "$timing_file" ]]
  jq -e '.elapsed_seconds >= 1 and .elapsed_seconds < 6' "$timing_file" >/dev/null
  printf 'quick hard deadline contract: PASS exit=%s\n' "$status"
}

common_env=(
  "PATH=$repo_root/node_modules/.bin:$bun_dir:$npm_dir:$jq_dir:$perl_dir:$python_dir:$bash_dir"
  "HOME=$test_root/home"
  "OPENCODE_BIN=$fake_opencode"
  "OPENCODE_AUTH_FILE=$test_root/auth.json"
  "EVIDENCE_ROOT=$test_root/evidence"
)

# Prove the shell entrypoint itself propagates a deliberate early failure.
run_expect_failure direct-early 97 env -i "${common_env[@]}" \
  OPENCODE_ROUTING_TEST_FAILURE=early bash "$harness"

# Prove the same failure is not swallowed by Bun's package-script wrapper.
run_expect_failure bun-early 97 env -i "${common_env[@]}" \
  OPENCODE_ROUTING_TEST_FAILURE=early "$bun_bin" run test:e2e:routing:live

# Prove the auth-file-only branch reaches the isolated env helper with no
# OPENAI credential entries; this is the Bash 3.2/set -u regression guard.
run_expect_failure auth-only-isolated 98 env -i "${common_env[@]}" \
  OPENCODE_ROUTING_TEST_FAILURE=isolated bash "$harness"

# Keep the quick path bounded and reject malformed overrides before any live
# model call. The default is 30 seconds, with a positive-integer override.
run_expect_config_failure invalid-quick-ceiling 2 'positive integer' env -i "${common_env[@]}" \
  OPENCODE_ROUTING_QUICK_MAX_SECONDS=not-a-number bash "$harness"
run_expect_config_failure provider-key-confusion 2 \
  'OPENCODE_LIVE_API_KEY is supported only for the openai provider' \
  env -i "${common_env[@]}" OPENCODE_LIVE_MODEL=opencode-go/gpt-5.6-luna \
  OPENCODE_LIVE_API_KEY=explicit-secret bash "$harness"
run_expect_quick_timeout env -i "${common_env[@]}" \
  OPENCODE_ROUTING_QUICK_MAX_SECONDS=1 bash "$harness"

printf '%s\n' 'routing live harness fail-closed contract: PASS'
