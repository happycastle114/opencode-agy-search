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

printf '%s\n' 'routing live harness fail-closed contract: PASS'
