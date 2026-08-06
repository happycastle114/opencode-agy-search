#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  printf 'usage: %s <case-evidence-directory>\n' "$0" >&2
  exit 64
fi

case_evidence=$1
if [[ ! -d "$case_evidence" ]]; then
  printf 'case evidence directory is unavailable: %s\n' "$case_evidence" >&2
  exit 66
fi
case_name=$(basename "$case_evidence")
case "$case_name" in
  quick|quick-preference|verified|synthesis|deep) ;;
  *)
    printf 'unknown routing case: %s\n' "$case_name" >&2
    exit 64
    ;;
esac

opencode_log="$case_evidence/opencode.jsonl"
argv_log="$case_evidence/agy-search-argv.jsonl"
result_log="$case_evidence/agy-search-results.jsonl"
agy_log="$case_evidence/agy-argv.jsonl"

for evidence_file in "$opencode_log" "$argv_log" "$result_log" "$agy_log"; do
  [[ -s "$evidence_file" ]] || {
    printf 'required routing evidence is empty or unavailable: %s\n' "$evidence_file" >&2
    exit 66
  }
done

jq -e -c . "$opencode_log" >/dev/null
jq -se '
  all(.[];
    .type != "error"
    and ((.error? // null) == null)
    and ((.part.error? // null) == null)
    and ((.part.state.error? // null) == null)
    and ((.part.state.status? // "completed") != "error")
    and (if .type == "tool_use"
      then ((.part.state.output? // "") | test("(?i)(jq: (error|parse error)|parse error:|compile error|command not found|no such file|file not found|timed out|permission denied)") | not)
      else true
    end)
  )
  and any(.[]; .type == "text" and ((.part.text? // "") | length > 0))
  and (([.[] | select(.type == "step_finish")][-1].part.reason? // "") == "stop")
' "$opencode_log" >/dev/null

jq -se '.[0] == ["--version"] and all(.[1:][]; any(.[]; . == "search" or . == "research" or . == "extract" or . == "map" or . == "crawl"))' "$argv_log" >/dev/null
jq -se 'length > 1 and all(.[]; .exit_code == 0)' "$result_log" >/dev/null
jq -se --slurpfile results "$result_log" '
  def canonical_argv_multiset:
    map(tojson) | sort;
  . as $arguments
  | ($arguments | length) == ($results | length)
  and (($arguments | canonical_argv_multiset)
    == ($results | map(.argv) | canonical_argv_multiset))
' "$argv_log" >/dev/null
jq -se '. == [["--version"]]' "$agy_log" >/dev/null

# Enforce the skill's lowest-sufficient-depth topology and bounded content
# budgets. The first ledger row is the one-time version preflight and is not a
# content call. A Verified temporal check is the only permitted second search;
# Synthesis and Deep may use bounded extract follow-ups, while Quick has no
# follow-up budget.
jq -se --arg case "$case_name" '
  def operation:
    first(.[] | select(. == "search" or . == "research" or . == "extract" or . == "map" or . == "crawl")) // null;
  def value_after($flag):
    .argv as $argv
    | ($argv | index($flag)) as $index
    | if $index == null or ($index + 1) >= ($argv | length)
      then null
      else $argv[$index + 1]
      end;
  def values_after($flag):
    .argv as $argv
    | [$argv | to_entries[] | select(.value == $flag) | .key as $index
      | if ($index + 1) >= ($argv | length)
        then null
        else $argv[$index + 1]
        end];
  def exact_flag($flag; $expected):
    values_after($flag) == [$expected];
  def configured($effort; $timeout):
    exact_flag("--effort"; $effort)
    and exact_flag("--timeout"; $timeout);
  def three_results:
    (values_after("-n") + values_after("--max-results")) == ["3"];
  def temporal:
    ((.argv | index("--verification")) as $index
      | ($index != null and .argv[$index + 1] == "temporal-comparison"));
  def quick_depth:
    length == 1
    and all(.op == "search" and configured("low"; "45") and three_results);
  def no_allowlist:
    all(.argv[]; . != "--domain" and . != "--source-url"
      and (startswith("--domain=") | not)
      and (startswith("--source-url=") | not));
  [.[1:][] | {argv: ., op: operation}] as $calls
  | ($calls | all(.op != null))
  and ($calls | if $case == "quick" then
    quick_depth
  elif $case == "quick-preference" then
    quick_depth and all(no_allowlist)
  elif $case == "verified" then
    (length >= 1 and length <= 2)
    and all(.op == "search" and configured("low"; "75") and three_results)
    and (map(select((.op == "search") and (temporal | not))) | length == 1)
    and (map(select((.op == "search") and temporal)) | length <= 1)
    and all(.[] | select(.op == "search"); ((.argv | index("--verification")) == null or temporal))
  elif $case == "synthesis" then
    (length >= 1 and length <= 4)
    and .[0].op == "research"
    and (map(select(.op == "research")) | length == 1)
    and all(.op == "research" or .op == "extract")
    and all(.[] | select(.op == "research"); configured("medium"; "120") and exact_flag("--max-sources"; "4"))
    and all(.[] | select(.op == "extract"); any(.argv[]; startswith("http://") or startswith("https://")))
  elif $case == "deep" then
    (length >= 1 and length <= 4)
    and .[0].op == "research"
    and ((map(select(.op == "research")) | length) >= 1 and (map(select(.op == "research")) | length) <= 2)
    and all(.op == "research" or .op == "extract")
    and all(.[] | select(.op == "research"); configured("high"; "180") and exact_flag("--max-sources"; "8"))
    and all(.[] | select(.op == "extract"); any(.argv[]; startswith("http://") or startswith("https://")))
    and ((map(select(.op == "research")) | length) < 2 or
      (map(select(.op == "research"))[1].argv | any(test("(?i)(thin|conflict|expansion|follow[- ]?up|prospective)"))))
  else false end)
' "$argv_log" >/dev/null

grep -F 'command -v agy-search' "$opencode_log" >/dev/null
grep -F 'command -v agy' "$opencode_log" >/dev/null
grep -F 'command -v curl' "$opencode_log" >/dev/null
jq -se 'any(.[]; .type == "tool_use" and .part.tool == "skill" and .part.state.status == "completed" and .part.state.input.name == "agy-search")' "$opencode_log" >/dev/null
[[ "$(jq -r '.sessionID' "$opencode_log" | sort -u | wc -l | tr -d ' ')" == 1 ]]

printf 'routing evidence gate: PASS %s\n' "$case_evidence"
