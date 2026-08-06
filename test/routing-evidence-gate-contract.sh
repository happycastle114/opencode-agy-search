#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd -P)
fixture_root="$repo_root/test/fixtures/routing-evidence-gate/clean"
gate="$repo_root/test/routing-evidence-gate.sh"
temp_base=$(cd "${TMPDIR:-/tmp}" && pwd -P)
test_root=$(mktemp -d "$temp_base/opencode-agy-routing-gate.XXXXXX")
touch "$test_root/.opencode-agy-routing-gate-owned"

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  case "$test_root" in
    "$temp_base"/opencode-agy-routing-gate.*)
      if [[ -f "$test_root/.opencode-agy-routing-gate-owned" ]]; then
        find "$test_root" -depth -delete
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

[[ -d "$fixture_root" ]]
[[ -f "$gate" ]]

copy_clean_evidence() {
  local name=$1
  local destination="$test_root/$name"
  cp -R "$fixture_root" "$destination"
  printf '%s\n' "$destination"
}

assert_gate_rejects() {
  local name=$1
  local evidence_dir=$2
  if bash "$gate" "$evidence_dir" >"$test_root/$name.stdout" 2>"$test_root/$name.stderr"; then
    printf 'gate accepted invalid evidence: %s\n' "$name" >&2
    return 1
  fi
  printf 'routing evidence gate rejection observed: %s\n' "$name"
}

copy_named_case() {
  local parent=$1
  local case_name=$2
  local destination="$test_root/$parent/$case_name"
  mkdir -p "$test_root/$parent"
  cp -R "$fixture_root" "$destination"
  printf '%s\n' "$destination"
}

clean_evidence=$(copy_clean_evidence quick)
bash "$gate" "$clean_evidence" >"$test_root/clean.stdout" 2>"$test_root/clean.stderr"
printf '%s\n' 'routing evidence gate acceptance observed: clean'

valid_synthesis=$(copy_named_case valid-synthesis synthesis)
jq -c 'if any(.[]; . == "search") then ["--effort","medium","--timeout","120","research","fixture","--max-sources","4"] else . end' \
  "$valid_synthesis/agy-search-argv.jsonl" >"$valid_synthesis/next.jsonl"
mv "$valid_synthesis/next.jsonl" "$valid_synthesis/agy-search-argv.jsonl"
jq -c 'if any(.argv[]; . == "search") then .argv = ["--effort","medium","--timeout","120","research","fixture","--max-sources","4"] else . end' \
  "$valid_synthesis/agy-search-results.jsonl" >"$valid_synthesis/next.jsonl"
mv "$valid_synthesis/next.jsonl" "$valid_synthesis/agy-search-results.jsonl"
bash "$gate" "$valid_synthesis" >"$test_root/valid-synthesis.stdout" 2>"$test_root/valid-synthesis.stderr"
printf '%s\n' 'routing evidence gate acceptance observed: valid-synthesis'

valid_parallel_synthesis=$(copy_named_case valid-parallel-synthesis synthesis)
jq -c 'if any(.[]; . == "search") then ["--effort","medium","--timeout","120","research","fixture","--max-sources","4"] else . end' \
  "$valid_parallel_synthesis/agy-search-argv.jsonl" >"$valid_parallel_synthesis/next.jsonl"
mv "$valid_parallel_synthesis/next.jsonl" "$valid_parallel_synthesis/agy-search-argv.jsonl"
jq -c 'if any(.argv[]; . == "search") then .argv = ["--effort","medium","--timeout","120","research","fixture","--max-sources","4"] else . end' \
  "$valid_parallel_synthesis/agy-search-results.jsonl" >"$valid_parallel_synthesis/next.jsonl"
mv "$valid_parallel_synthesis/next.jsonl" "$valid_parallel_synthesis/agy-search-results.jsonl"
printf '%s\n' '["extract","https://example.com/a"]' '["extract","https://example.com/b"]' \
  >>"$valid_parallel_synthesis/agy-search-argv.jsonl"
printf '%s\n' \
  '{"exit_code":0,"argv":["extract","https://example.com/b"]}' \
  '{"exit_code":0,"argv":["extract","https://example.com/a"]}' \
  >>"$valid_parallel_synthesis/agy-search-results.jsonl"
bash "$gate" "$valid_parallel_synthesis" >"$test_root/valid-parallel-synthesis.stdout" 2>"$test_root/valid-parallel-synthesis.stderr"
printf '%s\n' 'routing evidence gate acceptance observed: valid-parallel-synthesis'

valid_deep=$(copy_named_case valid-deep deep)
jq -c 'if any(.[]; . == "search") then ["--effort","high","--timeout","180","research","fixture","--max-sources","8"] else . end' \
  "$valid_deep/agy-search-argv.jsonl" >"$valid_deep/next.jsonl"
mv "$valid_deep/next.jsonl" "$valid_deep/agy-search-argv.jsonl"
jq -c 'if any(.argv[]; . == "search") then .argv = ["--effort","high","--timeout","180","research","fixture","--max-sources","8"] else . end' \
  "$valid_deep/agy-search-results.jsonl" >"$valid_deep/next.jsonl"
mv "$valid_deep/next.jsonl" "$valid_deep/agy-search-results.jsonl"
bash "$gate" "$valid_deep" >"$test_root/valid-deep.stdout" 2>"$test_root/valid-deep.stderr"
printf '%s\n' 'routing evidence gate acceptance observed: valid-deep'

nonzero_ledger=$(copy_named_case nonzero-result-ledger quick)
jq 'if .exit_code == 0 then .exit_code = 71 else . end' \
  "$nonzero_ledger/agy-search-results.jsonl" >"$nonzero_ledger/next.jsonl"
mv "$nonzero_ledger/next.jsonl" "$nonzero_ledger/agy-search-results.jsonl"
assert_gate_rejects nonzero-result-ledger "$nonzero_ledger"

agent_error=$(copy_named_case opencode-agent-error quick)
printf '%s\n' '{"type":"error","sessionID":"fixture-clean-session","error":{"name":"AgentError","data":{"message":"fixture agent failure"}}}' \
  >>"$agent_error/opencode.jsonl"
assert_gate_rejects opencode-agent-error "$agent_error"

tool_output_error=$(copy_named_case tool-use-output-error quick)
jq 'if .type == "tool_use" and .part.tool == "bash" then .part.state.output = "command not found" else . end' \
  "$tool_output_error/opencode.jsonl" >"$tool_output_error/next.jsonl"
mv "$tool_output_error/next.jsonl" "$tool_output_error/opencode.jsonl"
assert_gate_rejects tool-use-output-error "$tool_output_error"

tool_state_error=$(copy_named_case tool-use-state-error quick)
jq 'if .type == "tool_use" and .part.tool == "bash" then .part.state.status = "error" | .part.state.error = "fixture tool failure" else . end' \
  "$tool_state_error/opencode.jsonl" >"$tool_state_error/next.jsonl"
mv "$tool_state_error/next.jsonl" "$tool_state_error/opencode.jsonl"
assert_gate_rejects tool-use-state-error "$tool_state_error"

result_argv_mismatch=$(copy_named_case result-argv-mismatch quick)
jq -c 'if any(.argv[]; . == "search") then .argv = ["unrelated-command"] else . end' \
  "$result_argv_mismatch/agy-search-results.jsonl" >"$result_argv_mismatch/next.jsonl"
mv "$result_argv_mismatch/next.jsonl" "$result_argv_mismatch/agy-search-results.jsonl"
assert_gate_rejects result-argv-mismatch "$result_argv_mismatch"

unknown_case=$(copy_clean_evidence unknown)
assert_gate_rejects unknown-case "$unknown_case"

quick_over_budget=$(copy_named_case quick-over-budget quick)
printf '%s\n' '["extract","https://example.com/extra"]' >>"$quick_over_budget/agy-search-argv.jsonl"
printf '%s\n' '{"exit_code":0,"argv":["extract","https://example.com/extra"]}' >>"$quick_over_budget/agy-search-results.jsonl"
assert_gate_rejects quick-over-budget "$quick_over_budget"

valid_hard_quick=$(copy_named_case valid-hard-quick quick)
jq -c 'if any(.[]; . == "search") then . + ["--domain", "iana.org"] else . end' \
  "$valid_hard_quick/agy-search-argv.jsonl" >"$valid_hard_quick/next.jsonl"
mv "$valid_hard_quick/next.jsonl" "$valid_hard_quick/agy-search-argv.jsonl"
jq -c 'if any(.argv[]; . == "search") then .argv += ["--domain", "iana.org"] else . end' \
  "$valid_hard_quick/agy-search-results.jsonl" >"$valid_hard_quick/next.jsonl"
mv "$valid_hard_quick/next.jsonl" "$valid_hard_quick/agy-search-results.jsonl"
bash "$gate" "$valid_hard_quick" >"$test_root/valid-hard-quick.stdout" 2>"$test_root/valid-hard-quick.stderr"
printf '%s\n' 'routing evidence gate acceptance observed: valid-hard-quick'

valid_hard_quick_url=$(copy_named_case valid-hard-quick-url quick)
jq -c 'if any(.[]; . == "search") then . + ["--source-url", "https://www.iana.org/"] else . end' \
  "$valid_hard_quick_url/agy-search-argv.jsonl" >"$valid_hard_quick_url/next.jsonl"
mv "$valid_hard_quick_url/next.jsonl" "$valid_hard_quick_url/agy-search-argv.jsonl"
jq -c 'if any(.argv[]; . == "search") then .argv += ["--source-url", "https://www.iana.org/"] else . end' \
  "$valid_hard_quick_url/agy-search-results.jsonl" >"$valid_hard_quick_url/next.jsonl"
mv "$valid_hard_quick_url/next.jsonl" "$valid_hard_quick_url/agy-search-results.jsonl"
bash "$gate" "$valid_hard_quick_url" \
  >"$test_root/valid-hard-quick-url.stdout" 2>"$test_root/valid-hard-quick-url.stderr"
printf '%s\n' 'routing evidence gate acceptance observed: valid-hard-quick-url'

assert_quick_allowlist_rejected() {
  local name=$1
  local suffix=$2
  local evidence
  evidence=$(copy_named_case "$name" quick-preference)
  jq -c --argjson suffix "$suffix" \
    'if any(.[]; . == "search") then . + $suffix else . end' \
    "$evidence/agy-search-argv.jsonl" >"$evidence/next.jsonl"
  mv "$evidence/next.jsonl" "$evidence/agy-search-argv.jsonl"
  jq -c --argjson suffix "$suffix" \
    'if any(.argv[]; . == "search") then .argv += $suffix else . end' \
    "$evidence/agy-search-results.jsonl" >"$evidence/next.jsonl"
  mv "$evidence/next.jsonl" "$evidence/agy-search-results.jsonl"
  assert_gate_rejects "$name" "$evidence"
}

assert_quick_allowlist_rejected quick-preference-domain '["--domain", "iana.org"]'
assert_quick_allowlist_rejected quick-preference-domain-equals '["--domain=iana.org"]'
assert_quick_allowlist_rejected quick-preference-source-url '["--source-url", "https://www.iana.org/"]'
assert_quick_allowlist_rejected quick-preference-source-url-equals \
  '["--source-url=https://www.iana.org/"]'

verified_wrong_operation=$(copy_named_case verified-wrong-operation verified)
printf '%s\n' '["research","--effort","medium","--timeout","120","fixture"]' >>"$verified_wrong_operation/agy-search-argv.jsonl"
printf '%s\n' '{"exit_code":0,"argv":["research","--effort","medium","--timeout","120","fixture"]}' >>"$verified_wrong_operation/agy-search-results.jsonl"
assert_gate_rejects verified-wrong-operation "$verified_wrong_operation"

synthesis_wrong_operation=$(copy_named_case synthesis-wrong-operation synthesis)
jq -c 'if any(.[]; . == "search") then map(if . == "search" then "research" else . end) else . end' \
  "$synthesis_wrong_operation/agy-search-argv.jsonl" >"$synthesis_wrong_operation/next.jsonl"
mv "$synthesis_wrong_operation/next.jsonl" "$synthesis_wrong_operation/agy-search-argv.jsonl"
jq -c 'if any(.argv[]; . == "search") then .argv |= map(if . == "search" then "research" else . end) else . end' \
  "$synthesis_wrong_operation/agy-search-results.jsonl" >"$synthesis_wrong_operation/next.jsonl"
mv "$synthesis_wrong_operation/next.jsonl" "$synthesis_wrong_operation/agy-search-results.jsonl"
printf '%s\n' '["search","--effort","low","--timeout","45","fixture"]' >>"$synthesis_wrong_operation/agy-search-argv.jsonl"
printf '%s\n' '{"exit_code":0,"argv":["search","--effort","low","--timeout","45","fixture"]}' >>"$synthesis_wrong_operation/agy-search-results.jsonl"
assert_gate_rejects synthesis-wrong-operation "$synthesis_wrong_operation"

synthesis_missing_cap=$(copy_named_case synthesis-missing-cap synthesis)
jq -c 'if any(.[]; . == "search") then ["--effort","medium","--timeout","120","research","fixture"] else . end' \
  "$synthesis_missing_cap/agy-search-argv.jsonl" >"$synthesis_missing_cap/next.jsonl"
mv "$synthesis_missing_cap/next.jsonl" "$synthesis_missing_cap/agy-search-argv.jsonl"
jq -c 'if any(.argv[]; . == "search") then .argv = ["--effort","medium","--timeout","120","research","fixture"] else . end' \
  "$synthesis_missing_cap/agy-search-results.jsonl" >"$synthesis_missing_cap/next.jsonl"
mv "$synthesis_missing_cap/next.jsonl" "$synthesis_missing_cap/agy-search-results.jsonl"
assert_gate_rejects synthesis-missing-cap "$synthesis_missing_cap"

synthesis_duplicate_cap=$(copy_named_case synthesis-duplicate-cap synthesis)
jq -c 'if any(.[]; . == "search") then ["--effort","medium","--timeout","120","research","fixture","--max-sources","4","--max-sources","1"] else . end' \
  "$synthesis_duplicate_cap/agy-search-argv.jsonl" >"$synthesis_duplicate_cap/next.jsonl"
mv "$synthesis_duplicate_cap/next.jsonl" "$synthesis_duplicate_cap/agy-search-argv.jsonl"
jq -c 'if any(.argv[]; . == "search") then .argv = ["--effort","medium","--timeout","120","research","fixture","--max-sources","4","--max-sources","1"] else . end' \
  "$synthesis_duplicate_cap/agy-search-results.jsonl" >"$synthesis_duplicate_cap/next.jsonl"
mv "$synthesis_duplicate_cap/next.jsonl" "$synthesis_duplicate_cap/agy-search-results.jsonl"
assert_gate_rejects synthesis-duplicate-cap "$synthesis_duplicate_cap"

synthesis_duplicate_effort=$(copy_named_case synthesis-duplicate-effort synthesis)
jq -c 'if any(.[]; . == "search") then ["--effort","medium","--effort","low","--timeout","120","research","fixture","--max-sources","4"] else . end' \
  "$synthesis_duplicate_effort/agy-search-argv.jsonl" >"$synthesis_duplicate_effort/next.jsonl"
mv "$synthesis_duplicate_effort/next.jsonl" "$synthesis_duplicate_effort/agy-search-argv.jsonl"
jq -c 'if any(.argv[]; . == "search") then .argv = ["--effort","medium","--effort","low","--timeout","120","research","fixture","--max-sources","4"] else . end' \
  "$synthesis_duplicate_effort/agy-search-results.jsonl" >"$synthesis_duplicate_effort/next.jsonl"
mv "$synthesis_duplicate_effort/next.jsonl" "$synthesis_duplicate_effort/agy-search-results.jsonl"
assert_gate_rejects synthesis-duplicate-effort "$synthesis_duplicate_effort"

deep_narrowed_wrong_cap=$(copy_named_case deep-narrowed-wrong-cap deep)
jq -c 'if any(.[]; . == "search") then ["--effort","high","--timeout","180","research","fixture","--max-sources","8"] else . end' \
  "$deep_narrowed_wrong_cap/agy-search-argv.jsonl" >"$deep_narrowed_wrong_cap/next.jsonl"
mv "$deep_narrowed_wrong_cap/next.jsonl" "$deep_narrowed_wrong_cap/agy-search-argv.jsonl"
jq -c 'if any(.argv[]; . == "search") then .argv = ["--effort","high","--timeout","180","research","fixture","--max-sources","8"] else . end' \
  "$deep_narrowed_wrong_cap/agy-search-results.jsonl" >"$deep_narrowed_wrong_cap/next.jsonl"
mv "$deep_narrowed_wrong_cap/next.jsonl" "$deep_narrowed_wrong_cap/agy-search-results.jsonl"
printf '%s\n' '["--effort","high","--timeout","180","research","thin conflict follow-up","--max-sources","4"]' \
  >>"$deep_narrowed_wrong_cap/agy-search-argv.jsonl"
printf '%s\n' '{"exit_code":0,"argv":["--effort","high","--timeout","180","research","thin conflict follow-up","--max-sources","4"]}' \
  >>"$deep_narrowed_wrong_cap/agy-search-results.jsonl"
assert_gate_rejects deep-narrowed-wrong-cap "$deep_narrowed_wrong_cap"

deep_duplicate_cap=$(copy_named_case deep-duplicate-cap deep)
jq -c 'if any(.[]; . == "search") then ["--effort","high","--timeout","180","research","fixture","--max-sources","8","--max-sources","4"] else . end' \
  "$deep_duplicate_cap/agy-search-argv.jsonl" >"$deep_duplicate_cap/next.jsonl"
mv "$deep_duplicate_cap/next.jsonl" "$deep_duplicate_cap/agy-search-argv.jsonl"
jq -c 'if any(.argv[]; . == "search") then .argv = ["--effort","high","--timeout","180","research","fixture","--max-sources","8","--max-sources","4"] else . end' \
  "$deep_duplicate_cap/agy-search-results.jsonl" >"$deep_duplicate_cap/next.jsonl"
mv "$deep_duplicate_cap/next.jsonl" "$deep_duplicate_cap/agy-search-results.jsonl"
assert_gate_rejects deep-duplicate-cap "$deep_duplicate_cap"

deep_duplicate_timeout=$(copy_named_case deep-duplicate-timeout deep)
jq -c 'if any(.[]; . == "search") then ["--effort","high","--timeout","180","--timeout","120","research","fixture","--max-sources","8"] else . end' \
  "$deep_duplicate_timeout/agy-search-argv.jsonl" >"$deep_duplicate_timeout/next.jsonl"
mv "$deep_duplicate_timeout/next.jsonl" "$deep_duplicate_timeout/agy-search-argv.jsonl"
jq -c 'if any(.argv[]; . == "search") then .argv = ["--effort","high","--timeout","180","--timeout","120","research","fixture","--max-sources","8"] else . end' \
  "$deep_duplicate_timeout/agy-search-results.jsonl" >"$deep_duplicate_timeout/next.jsonl"
mv "$deep_duplicate_timeout/next.jsonl" "$deep_duplicate_timeout/agy-search-results.jsonl"
assert_gate_rejects deep-duplicate-timeout "$deep_duplicate_timeout"

deep_over_budget=$(copy_named_case deep-over-budget deep)
printf '%s\n' '["research","--effort","high","--timeout","180","third expansion"]' >>"$deep_over_budget/agy-search-argv.jsonl"
printf '%s\n' '{"exit_code":0,"argv":["research","--effort","high","--timeout","180","third expansion"]}' >>"$deep_over_budget/agy-search-results.jsonl"
assert_gate_rejects deep-over-budget "$deep_over_budget"

printf '%s\n' 'routing evidence gate contract: PASS'
