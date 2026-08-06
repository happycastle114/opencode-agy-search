#!/usr/bin/env bash
set -euo pipefail

opencode_bin=${OPENCODE_BIN:-/opt/homebrew/bin/opencode}
live_model=${OPENCODE_LIVE_MODEL:-openai/gpt-5.6-luna-fast}
live_model_provider=${live_model%%/*}
quick_max_elapsed_seconds=${OPENCODE_ROUTING_QUICK_MAX_SECONDS:-30}
auth_file=${OPENCODE_AUTH_FILE:-${HOME:?}/.local/share/opencode/auth.json}
evidence_root=${EVIDENCE_ROOT:-$PWD/.omo/evidence/current-skill-routing-live-20260806}
script_dir=$(cd "$(dirname "$0")" && pwd -P)
routing_evidence_gate="$script_dir/routing-evidence-gate.sh"
routing_auth_helper="$script_dir/routing-live-auth.sh"

# This harness uses a live OpenCode model with a deterministic fixture CLI. It
# proves skill/depth routing and error propagation, not web-search accuracy.

if [[ ! -x "$opencode_bin" ]] || [[ "$($opencode_bin --version)" != 1.18.11 ]]; then
  printf 'OpenCode 1.18.11 is required: %s\n' "$opencode_bin" >&2
  exit 2
fi
for executable in jq npm perl python3; do
  command -v "$executable" >/dev/null || {
    printf 'required executable is unavailable: %s\n' "$executable" >&2
    exit 2
  }
done
[[ -f "$routing_evidence_gate" ]] || {
  printf 'routing evidence gate is unavailable: %s\n' "$routing_evidence_gate" >&2
  exit 2
}
[[ -f "$routing_auth_helper" ]] || {
  printf 'routing auth helper is unavailable: %s\n' "$routing_auth_helper" >&2
  exit 2
}
# shellcheck source=routing-live-auth.sh
source "$routing_auth_helper"
if ! live_api_key=$(resolve_live_api_key_for_provider \
  "$live_model_provider" \
  "${OPENCODE_LIVE_API_KEY:-}" \
  "${OPENAI_API_KEY:-}"); then
  exit 2
fi
if ! [[ "$quick_max_elapsed_seconds" =~ ^[1-9][0-9]*$ ]]; then
  printf 'OPENCODE_ROUTING_QUICK_MAX_SECONDS must be a positive integer\n' >&2
  exit 2
fi
if [[ ! -f "$auth_file" && -z "$live_api_key" ]]; then
  printf 'OpenCode auth file or live API key is required\n' >&2
  exit 2
fi
credential_env=()
if [[ -n "$live_api_key" ]]; then
  credential_env+=("OPENAI_API_KEY=$live_api_key")
fi
if [[ "$live_model_provider" == openai && -n "${OPENAI_BASE_URL:-}" ]]; then
  credential_env+=("OPENAI_BASE_URL=$OPENAI_BASE_URL")
fi

run_isolated() {
  if [[ "${#credential_env[@]}" -gt 0 ]]; then
    env -i "${isolated_env[@]}" "${credential_env[@]}" "$@"
  else
    # Bash 3.2 raises an unbound-variable error for an empty array expanded
    # with set -u. Keep the empty credential case out of the expansion.
    env -i "${isolated_env[@]}" "$@"
  fi
}

# Test-only failure injection lets the harness contract prove that both this
# script and its Bun wrapper fail closed without contacting a model. It is
# intentionally opt-in and exits before creating an evidence run directory.
if [[ "${OPENCODE_ROUTING_TEST_FAILURE:-}" == early ]]; then
  printf '%s\n' 'injected routing harness failure' >&2
  exit 97
fi

temp_base=$(cd "${TMPDIR:-/tmp}" && pwd -P)
e2e_root=$(mktemp -d "$temp_base/opencode-agy-routing.XXXXXX")
touch "$e2e_root/.opencode-agy-routing-owned"
run_id=$(date -u +%Y%m%dT%H%M%SZ)-$$
run_dir="$evidence_root/$run_id"
mkdir -p "$run_dir"

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if [[ "$status" -ne 0 ]]; then
    printf 'routing live E2E failed; evidence retained at %s\n' "$run_dir" >&2
  fi
  case "$e2e_root" in
    "$temp_base"/opencode-agy-routing.*)
      if [[ -f "$e2e_root/.opencode-agy-routing-owned" ]]; then
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

mkdir -p "$e2e_root/package" "$e2e_root/bin"
npm pack --json --pack-destination "$e2e_root/package" >"$run_dir/npm-pack.json"
plugin_tarball=$(find "$e2e_root/package" -maxdepth 1 -type f -name '*.tgz')
[[ -n "$plugin_tarball" ]]
tar -xzf "$plugin_tarball" -C "$e2e_root/package"
plugin_root="$e2e_root/package/package"
plugin_entry="$plugin_root/index.ts"
skill_directory="$plugin_root/skills/agy-search"
jq -e '.version == "0.3.6"' "$plugin_root/package.json" >/dev/null
[[ -f "$plugin_entry" && -f "$skill_directory/SKILL.md" ]]
cp "$plugin_root/package.json" "$run_dir/packed-package.json"
shasum -a 256 "$skill_directory/SKILL.md" >"$run_dir/packed-skill.sha256"
plugin_url=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve().as_uri())' "$plugin_entry")

cat >"$e2e_root/bin/agy-search" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
: "${AGY_ROUTING_ARGV_LOG:?}"
: "${AGY_ROUTING_RESULT_LOG:?}"
: "${AGY_ROUTING_CASE:?}"
original_arguments=("$@")
record_exit() {
  local exit_code=$?
  trap - EXIT
  jq -cn --argjson exit_code "$exit_code" --args \
    '{exit_code:$exit_code,argv:$ARGS.positional}' -- "${original_arguments[@]}" \
    >>"$AGY_ROUTING_RESULT_LOG" || exit 70
  exit "$exit_code"
}
trap record_exit EXIT
jq -cn --args '$ARGS.positional' -- "$@" >>"$AGY_ROUTING_ARGV_LOG"
if [[ "${1:-}" == "--version" ]]; then
  printf 'agy-search 0.2.5\n'
  exit 0
fi
command_name=
output_path=
previous=
for argument in "$@"; do
  case "$previous" in
    output) output_path=$argument ;;
  esac
  previous=
  case "$argument" in
    search|research|extract|map|crawl) command_name=$argument ;;
    -o|--output) previous=output ;;
  esac
done
[[ -n "$command_name" ]] || exit 64
arguments="$*"
if [[ "$command_name" == research ]]; then
  if [[ "$AGY_ROUTING_CASE" == deep ]]; then
    payload='{"object":"research","title":"Hospital AI-assisted diagnosis assessment","summary":"Evidence is mixed: assistive systems can improve accuracy in selected retrospective or controlled tasks, but gains do not consistently establish better patient outcomes and can introduce false positives, automation bias, subgroup inequity, drift, and workflow failures. Adopt only a narrow assistive use case through a staged, monitored deployment with clinician authority, local prospective validation, governance, incident reporting, and rollback criteria; do not authorize autonomous diagnosis.","findings":[{"title":"Conflicting clinical evidence","summary":"Benchmark accuracy and selected clinician-assistance gains are not equivalent to prospective patient benefit; external validity, spectrum bias, false positives, and automation bias remain material limitations.","citations":["https://www.nature.com/articles/s41591-021-01514-0","https://www.nejm.org/doi/full/10.1056/NEJMra2302038"]},{"title":"Regulation and accountability","summary":"Device authorization and risk classification do not prove local effectiveness. Hospitals retain duties for intended-use controls, human oversight, change management, and post-deployment monitoring.","citations":["https://www.fda.gov/medical-devices/software-medical-device-samd/artificial-intelligence-enabled-medical-devices","https://digital-strategy.ec.europa.eu/en/policies/regulatory-framework-ai"]},{"title":"Bias and governance","summary":"Equity assessment must be subgroup-specific and locally validated; governance should map, measure, manage, and document foreseeable harms and model drift.","citations":["https://www.who.int/publications/i/item/9789240029200","https://www.nist.gov/itl/ai-risk-management-framework"]},{"title":"Security and operations","summary":"Protected health information, vendor access, integration failures, downtime, incident response, and cyber risk require contractual controls, least privilege, auditability, fallback workflows, and continuous surveillance.","citations":["https://www.hhs.gov/hipaa/for-professionals/security/index.html","https://www.nice.org.uk/corporate/ecd7"]}],"sources":[{"title":"FDA AI-enabled medical devices","url":"https://www.fda.gov/medical-devices/software-medical-device-samd/artificial-intelligence-enabled-medical-devices","snippet":"FDA lifecycle oversight and transparency information for AI-enabled medical devices; listing does not establish local patient benefit.","date":null,"last_updated":"2026-07-01"},{"title":"WHO ethics and governance of AI for health","url":"https://www.who.int/publications/i/item/9789240029200","snippet":"WHO guidance emphasizes autonomy, safety, transparency, accountability, equity, and sustainability.","date":"2021-06-28","last_updated":null},{"title":"NIST AI Risk Management Framework","url":"https://www.nist.gov/itl/ai-risk-management-framework","snippet":"NIST framework organizes governance, mapping, measurement, and management of AI risks.","date":"2023-01-26","last_updated":"2026-01-15"},{"title":"Clinical AI evidence review","url":"https://www.nature.com/articles/s41591-021-01514-0","snippet":"Peer-reviewed evidence review identifies external validation, reporting, bias, and implementation limitations.","date":"2021-09-30","last_updated":null},{"title":"NEJM artificial intelligence in medicine review","url":"https://www.nejm.org/doi/full/10.1056/NEJMra2302038","snippet":"Clinical review distinguishes performance studies from demonstrated clinical utility and discusses human-AI interaction risks.","date":"2024-03-21","last_updated":null},{"title":"EU regulatory framework for AI","url":"https://digital-strategy.ec.europa.eu/en/policies/regulatory-framework-ai","snippet":"EU framework treats specified medical AI uses as high risk with risk management, data, oversight, and monitoring obligations.","date":null,"last_updated":"2026-06-01"},{"title":"HHS HIPAA Security Rule","url":"https://www.hhs.gov/hipaa/for-professionals/security/index.html","snippet":"Security safeguards apply to electronic protected health information and associated operational controls.","date":null,"last_updated":"2026-05-01"},{"title":"NICE Evidence Standards Framework","url":"https://www.nice.org.uk/corporate/ecd7","snippet":"Evidence standards scale evaluation requirements with digital health technology function and risk.","date":null,"last_updated":"2026-02-01"}]}'
  else
    payload='{"object":"research","title":"Bun and Node.js compatibility and support comparison","summary":"Node.js is the lower-risk default for an established backend because it is the native compatibility target and publishes a multi-stage LTS lifecycle. Bun is viable for a controlled dependency set after compatibility testing, but its Node API surface includes partial and missing areas and its rapid release cadence is not equivalent to Node LTS. Independent comparisons support workload-specific evaluation, not a universal migration.","findings":[{"title":"Node API compatibility","summary":"Bun implements common Node APIs but its own compatibility matrix identifies partial or missing surfaces. Native addons, uncommon APIs, framework internals, and subtle runtime behavior require application-level testing before adoption.","citations":["https://bun.sh/docs/runtime/nodejs-apis","https://betterstack.com/community/guides/scaling-nodejs/nodejs-vs-bun/"]},{"title":"Release support","summary":"Node.js publishes Current, Active LTS, and Maintenance LTS phases with dated support windows. Bun publishes frequent releases and changelogs, but the returned evidence does not establish a matching multi-year LTS guarantee; teams must verify vendor support requirements separately.","citations":["https://nodejs.org/en/about/previous-releases","https://blog.logrocket.com/bun-vs-node-js/"]},{"title":"Independent evidence","summary":"Independent engineering comparisons describe Bun speed and integrated tooling benefits while warning that benchmarks are workload-dependent and ecosystem or compatibility gaps can dominate production outcomes.","citations":["https://betterstack.com/community/guides/scaling-nodejs/nodejs-vs-bun/","https://blog.logrocket.com/bun-vs-node-js/"]},{"title":"Recommendation","summary":"Keep Node.js as the default for broad package compatibility, native dependencies, conservative support needs, and mature operations. Pilot Bun for bounded greenfield services only after dependency, load, observability, deployment, rollback, and upgrade tests pass.","citations":["https://bun.sh/docs/runtime/nodejs-apis","https://nodejs.org/en/about/previous-releases","https://betterstack.com/community/guides/scaling-nodejs/nodejs-vs-bun/"]}],"sources":[{"title":"Bun Node.js compatibility","url":"https://bun.sh/docs/runtime/nodejs-apis","snippet":"Bun documents implemented, partial, and incomplete Node.js API surfaces; compatibility is not blanket equivalence and must be tested for the selected dependency graph.","date":null,"last_updated":"2026-07-01"},{"title":"Node.js releases","url":"https://nodejs.org/en/about/previous-releases","snippet":"Node.js documents Current, Active LTS, and Maintenance LTS release phases and dated support windows for production planning.","date":null,"last_updated":"2026-07-01"},{"title":"Better Stack Bun versus Node.js","url":"https://betterstack.com/community/guides/scaling-nodejs/nodejs-vs-bun/","snippet":"Independent engineering comparison covers workload-sensitive benchmarks, compatibility, native modules, ecosystem maturity, and production tradeoffs with methodology caveats.","date":"2025-05-15","last_updated":null},{"title":"LogRocket Bun versus Node.js","url":"https://blog.logrocket.com/bun-vs-node-js/","snippet":"Independent technical analysis compares compatibility, release maturity, tooling, ecosystem, performance, and migration risk and does not establish a universal winner.","date":"2025-04-10","last_updated":null}]}'
  fi
elif [[ "$command_name" == extract ]]; then
  payload=$(jq -cn --args '$ARGS.positional | map(select(startswith("http"))) | {object:"extract",results:map(. as $url | {url:$url,title:"Extracted canonical source",content:(if ($url | contains("bun.sh")) then "Bun documents its integrated tooling and identifies implemented, partial, and missing Node.js API compatibility; teams must test native addons and production workloads." elif ($url | contains("nodejs.org")) then "Node.js documents active and maintenance LTS release lines, API stability, and a mature operational ecosystem." elif ($url | contains("betterstack.com")) then "This independent engineering comparison reports workload-dependent benchmark results, methodology caveats, compatibility tradeoffs, and no universal runtime winner." elif ($url | contains("logrocket.com")) then "This independent technical analysis compares performance, ecosystem maturity, tooling, and migration risk, and recommends workload-specific evaluation." elif ($url | contains("fda.gov")) then "FDA lifecycle information covers AI-enabled medical devices; authorization does not prove local clinical benefit and post-deployment monitoring remains necessary." elif ($url | contains("who.int")) then "WHO guidance requires safety, transparency, accountability, autonomy, equity, and sustainability for health AI." elif ($url | contains("nist.gov")) then "NIST organizes AI risk governance around govern, map, measure, and manage functions with ongoing monitoring." elif (($url | contains("nature.com")) or ($url | contains("nejm.org"))) then "Peer-reviewed clinical evidence distinguishes retrospective accuracy from prospective patient outcomes and reports external-validity, bias, and human-interaction limitations." else "The canonical source supports governance, security, privacy, risk-tiering, evidence, and continuous monitoring requirements for high-stakes clinical AI." end)})}' -- "$@")
elif [[ "$arguments" == *Bun* ]]; then
  payload='{"object":"search","query":"fixture","results":[{"title":"Bun v1.3.0","url":"https://bun.sh/blog/bun-v1.3","snippet":"Bun v1.3.0 is the current stable release as of 2026-08-05.","date":"2026-08-05","last_updated":null}],"sources":[{"title":"Bun v1.3.0","url":"https://bun.sh/blog/bun-v1.3","snippet":"Bun v1.3.0 is the current stable release as of 2026-08-05.","date":"2026-08-05","last_updated":null}]}'
else
  payload=$(jq -cn --arg object "$command_name" '{object:$object,query:"fixture",results:[{title:"France facts",url:"https://www.diplomatie.gouv.fr/en/coming-to-france/france-facts/",snippet:"Paris is the capital of France.",date:null,last_updated:null}],sources:[{title:"France facts",url:"https://www.diplomatie.gouv.fr/en/coming-to-france/france-facts/",snippet:"Paris is the capital of France.",date:null,last_updated:null}]}')
fi
if [[ -n "$output_path" ]]; then
  mkdir -p "$(dirname "$output_path")"
  printf '%s\n' "$payload" >"$output_path"
else
  printf '%s\n' "$payload"
fi
SHIM

cat >"$e2e_root/bin/agy" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
: "${AGY_ROUTING_AGY_LOG:?}"
jq -cn --args '$ARGS.positional' -- "$@" >>"$AGY_ROUTING_AGY_LOG"
[[ "${1:-}" == "--version" ]] || exit 64
printf '1.1.10\n'
SHIM
chmod +x "$e2e_root/bin/agy-search" "$e2e_root/bin/agy"

case_names=(quick-preference verified synthesis deep)
prompts=(
  'Use the agy-search skill and complete this task: What is IANA? Prefer IANA, but other sources are allowed.'
  'Use the agy-search skill and complete this task: As of 2026-08-06, what is the current stable release version of Bun?'
  'Use the agy-search skill and complete this task: Compare Bun and Node.js for a backend team on Node API compatibility and release support, combining independent sources.'
  'Use the agy-search skill and complete this task: For a high-stakes hospital decision with conflicting evidence, assess autonomous AI diagnosis versus monitored clinician decision support.'
)
jq -n --arg model "$live_model" --args '$ARGS.positional | {model:$model,prompts:.}' -- "${prompts[@]}" >"$run_dir/scenarios.json"

for index in "${!case_names[@]}"; do
  case_name=${case_names[$index]}
  case_root="$e2e_root/$case_name"
  case_evidence="$run_dir/$case_name"
  mkdir -p "$case_root"/{config,home,tmp,workspace,xdg/cache,xdg/config,xdg/data/opencode,xdg/state} "$case_evidence"
  link_opencode_auth_for_provider \
    "$live_model_provider" \
    "$live_api_key" \
    "$auth_file" \
    "$case_root/xdg/data/opencode/auth.json"
  config_path="$case_root/config/opencode.json"
  jq -n --arg plugin "$plugin_url" '{"$schema":"https://opencode.ai/config.json",plugin:[$plugin],permission:{bash:"allow",webfetch:"deny",websearch:"deny",external_directory:{"*":"allow"}}}' >"$config_path"
  argv_log="$case_evidence/agy-search-argv.jsonl"
  result_log="$case_evidence/agy-search-results.jsonl"
  agy_log="$case_evidence/agy-argv.jsonl"
  : >"$argv_log"
  : >"$result_log"
  : >"$agy_log"
  isolated_env=(
    "PATH=$e2e_root/bin:$(dirname "$opencode_bin"):/opt/homebrew/bin:/usr/bin:/bin"
    "HOME=$case_root/home"
    "XDG_CONFIG_HOME=$case_root/xdg/config"
    "XDG_DATA_HOME=$case_root/xdg/data"
    "XDG_CACHE_HOME=$case_root/xdg/cache"
    "XDG_STATE_HOME=$case_root/xdg/state"
    "TMPDIR=$case_root/tmp"
    "OPENCODE_CONFIG=$config_path"
    "OPENCODE_CONFIG_DIR=$case_root/config"
    "AGY_SEARCH_AGY_PATH=$e2e_root/bin/agy"
    "AGY_ROUTING_ARGV_LOG=$argv_log"
    "AGY_ROUTING_RESULT_LOG=$result_log"
    "AGY_ROUTING_CASE=$case_name"
    "AGY_ROUTING_AGY_LOG=$agy_log"
    "CI=1"
    "NO_COLOR=1"
    "TERM=dumb"
  )

  if [[ "$index" -eq 0 && "${OPENCODE_ROUTING_TEST_FAILURE:-}" == isolated ]]; then
    # Exercise the auth-file-only branch with an empty credential array before
    # any model call. The contract test supplies a harmless version-only fake.
    run_isolated "$opencode_bin" --version >/dev/null
    printf '%s\n' 'injected isolated-environment harness failure' >&2
    exit 98
  fi
  if [[ "$index" -eq 0 ]]; then
    run_isolated "$opencode_bin" debug config >"$run_dir/resolved-config.json"
    run_isolated "$opencode_bin" debug skill >"$run_dir/debug-skill.txt"
  fi
  case_started_at=$(date +%s)
  case_process_timeout=240
  if [[ "$case_name" == quick-preference ]]; then
    case_process_timeout=$quick_max_elapsed_seconds
  fi
  case_status=0
  set +e
  (
    cd "$case_root/workspace"
    run_isolated perl -e 'alarm shift; exec @ARGV' "$case_process_timeout" \
      "$opencode_bin" run --model "$live_model" --format json "${prompts[$index]}" \
      >"$case_evidence/opencode.jsonl" 2>"$case_evidence/opencode.stderr"
  )
  case_status=$?
  set -e
  case_finished_at=$(date +%s)
  case_elapsed_seconds=$((case_finished_at - case_started_at))
  jq -n --argjson started "$case_started_at" --argjson finished "$case_finished_at" --argjson elapsed "$case_elapsed_seconds" '{started_at_epoch:$started,finished_at_epoch:$finished,elapsed_seconds:$elapsed}' >"$case_evidence/timing.json"
  if [[ "$case_status" -ne 0 ]]; then
    if [[ "$case_name" == quick-preference && "$case_status" -eq 142 ]]; then
      printf 'quick routing scenario hit %s second hard deadline\n' \
        "$quick_max_elapsed_seconds" >&2
      exit 124
    fi
    printf 'routing scenario %s failed with exit %s\n' "$case_name" "$case_status" >&2
    exit "$case_status"
  fi
  if [[ "$case_name" == quick-preference && "$case_elapsed_seconds" -gt "$quick_max_elapsed_seconds" ]]; then
    printf 'quick routing scenario exceeded %s second ceiling: %s seconds\n' \
      "$quick_max_elapsed_seconds" "$case_elapsed_seconds" >&2
    exit 124
  fi
done

grep -F "$plugin_entry" "$run_dir/resolved-config.json" >/dev/null
grep -F "$skill_directory" "$run_dir/resolved-config.json" >/dev/null
grep -F 'agy-search' "$run_dir/debug-skill.txt" >/dev/null

for case_name in "${case_names[@]}"; do
  case_evidence="$run_dir/$case_name"
  [[ ! -s "$case_evidence/opencode.stderr" ]]
  bash "$routing_evidence_gate" "$case_evidence"
  jq -r '.sessionID' "$case_evidence/opencode.jsonl" | sort -u | tee -a "$run_dir/session-ids.txt" >/dev/null
done
[[ "$(sort -u "$run_dir/session-ids.txt" | wc -l | tr -d ' ')" == 4 ]]

jq -n --arg model "$live_model" --arg evidence "$run_dir" '{result:"PASS",proof:"live_model_routing_with_fixture_cli",accuracy_proof:false,opencode_version:"1.18.11",model:$model,packed_plugin_version:"0.3.6",fresh_sessions:4,cases:{quick_preference:"PASS",verified:"PASS",synthesis:"PASS",deep:"PASS"},evidence:$evidence}' | tee "$run_dir/summary.json"
