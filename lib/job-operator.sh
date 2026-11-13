#!/usr/bin/env bash
# Walkaway job operator: acts on a scheduled job (jobs.yaml) that the supervisor's job watch marked FAILED.
#
#   job-operator.sh diagnose <job> <date>   read-only diagnosis (headless claude) -> incident file, then either a
#                                           template-v2 fix plan queued/launched in the owner repo (FIXING) or
#                                           ONE question to Jim (ESCALATED)
#   job-operator.sh progress <job> <date>   FIXING: follow the fix build; once it MERGED run the job's safe retry
#                                           path once (if any); the job watch confirms OK on its next check
#
# The model only reads (Read/Glob/Grep, git log/show). Evidence rows are gathered here with the same read-only
# checks the job watch uses (keys never leave lib/jobs.sh). Every action (write incident, render plan, queue,
# launch, retry) is done in shell. One auto-fix build per job per day; one builder per repo (queue otherwise).
#
# Fix workspace: $WALKAWAY_HOME/job-fixes/<job>-<date>/handoff/{job-incident-<job>-<date>.md,
# build-plan-<feature>.md, evidence-<job>-<date>.json}. The plan names the owner repo in "## Repo", so walkaway
# launches it there without writing into another builder's checkout; the fix build's Phase 0 commits the plan
# and the incident into the owner repo's handoff/ on its branch.

set -uo pipefail

JOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/jobs.sh
source "${JOP_DIR}/jobs.sh"
# operator.sh brings registry/notify/supervisor + _kill_tree, _other_active_build, _sync_default.
# shellcheck disable=SC2034  # read by operator.sh _other_active_build (skips this name)
FEATURE="job-operator"
# shellcheck source=lib/operator.sh
source "${JOP_DIR}/operator.sh"

WALKAWAY_JOB_OPERATOR_PROMPT="${WALKAWAY_JOB_OPERATOR_PROMPT:-${JOP_DIR}/../templates/job-operator-prompt.md}"
WALKAWAY_JOB_RETRY_TIMEOUT="${WALKAWAY_JOB_RETRY_TIMEOUT:-60}"

_jo_ws() { echo "${WALKAWAY_HOME}/job-fixes/$1-$2/handoff"; }

# ── read-only diagnosis ──────────────────────────────────────────────────────

JOB_DECISION_SCHEMA='{"type":"object","properties":{
 "decision":{"type":"string","enum":["fix","escalate"]},
 "protected_hit":{"type":"boolean","description":"true if the cause, the fix or its verification touches ANY protected action"},
 "needs_live_action":{"type":"boolean","description":"true if proving the fix needs the job live action (opt-in submit, publish, login)"},
 "confidence":{"type":"string","enum":["high","medium","low"]},
 "cause":{"type":"string","description":"one paragraph: the failure cause, pointing at rows/log lines and file:line"},
 "evidence":{"type":"array","items":{"type":"string"},"description":"exact rows (timestamp + fields), log lines, file:line refs"},
 "question":{"type":"string","description":"escalate: ONE question for Jim, one line"},
 "fix":{"type":"object","properties":{
   "title":{"type":"string"},"goal":{"type":"string"},
   "what_to_build":{"type":"array","items":{"type":"string"}},
   "acceptance_criteria":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"text":{"type":"string"},"evidence_file":{"type":"string"}},"required":["id","text","evidence_file"]}},
   "regression_fixture":{"type":"string","description":"the fixture built from this incident real rows; must fail on current code"},
   "files_expected":{"type":"array","items":{"type":"string"}},
   "do_not_build":{"type":"array","items":{"type":"string"}},
   "stop_rules":{"type":"array","items":{"type":"string"}}}}},
 "required":["decision","protected_hit","needs_live_action","confidence","cause","evidence"]}'

# _jask <owner-repo> <ws> <task> -> structured decision JSON (empty on failure/timeout)
_jask() {
  local repo="$1" ws="$2" task="$3" out
  out=$(mktemp)
  (
    cd "$repo" && "$WALKAWAY_OPERATOR_CMD" -p "$task" \
      --append-system-prompt-file "$WALKAWAY_JOB_OPERATOR_PROMPT" \
      --output-format json --json-schema "$JOB_DECISION_SCHEMA" --no-session-persistence \
      --add-dir "$ws" --add-dir "$(dirname "$WALKAWAY_PROTOCOL_PATH")" \
      --allowedTools Read Glob Grep "Bash(git log:*)" "Bash(git show:*)" "Bash(git diff:*)" \
        "Bash(jq:*)" "Bash(ls:*)" "Bash(wc:*)" "Bash(head:*)" "Bash(tail:*)" "Bash(cat:*)" \
      --disallowedTools Edit Write NotebookEdit "Bash(curl:*)" "Bash(git push:*)" "Bash(git commit:*)" "Bash(rm:*)" "Bash(open:*)"
  ) > "$out" 2>>"${WALKAWAY_HOME}/logs/job-operator.stderr.log" &
  local cpid=$! waited=0
  while kill -0 "$cpid" 2>/dev/null; do
    if (( waited >= WALKAWAY_OPERATOR_TIMEOUT )); then _kill_tree "$cpid"; break; fi
    sleep 5; waited=$((waited + 5))
  done
  wait "$cpid" 2>/dev/null
  jq -c '.structured_output // empty' "$out" 2>/dev/null
  rm -f "$out"
}

_md_list() { jq -r "(${1} // []) | map(\"- \" + .) | .[]"; }

# ── incident + plan rendering ────────────────────────────────────────────────

# _write_incident <ws> <job> <date> <decision-json> <evidence-json> <outcome-line>
_write_incident() {
  local ws="$1" job="$2" d="$3" dec="$4" ev="$5" outcome="$6" f
  f="$ws/job-incident-${job}-${d}.md"
  {
    printf '# Job incident - %s - %s\n\n' "$job" "$d"
    printf 'Written by the walkaway job operator (read-only diagnosis) at %s.\n\n' "$(_et)"
    printf '## Failure\n%s\n\n' "$(jq -r '.state.failed_detail // .check.detail' <<< "$ev")"
    printf '## Cause\n%s\n\n' "$(jq -r '.cause // "(no diagnosis returned)"' <<< "$dec")"
    printf '## Evidence\n'; _md_list '.evidence' <<< "$dec"
    printf '\n## Decision\n%s\n' "$outcome"
    printf -- '- confidence: %s; protected_hit: %s; needs_live_action: %s\n' \
      "$(jq -r '.confidence // "-"' <<< "$dec")" "$(jq -r '.protected_hit // "-"' <<< "$dec")" "$(jq -r '.needs_live_action // "-"' <<< "$dec")"
    printf '\n## Check rows (read-only, %s)\n' "$(jq -r '.check.checked_at' <<< "$ev")"
    jq -r '.check.paths | to_entries[] | "- query \(.key): `\(.value)`"' <<< "$ev"
    printf '\n```json\n%s\n```\n' "$(jq '{verdict: .check.verdict, detail: .check.detail, rows: .check.rows, sample: .check.sample, log: .check.log}' <<< "$ev" | head -c 6000)"
    printf '\n## Diagnose rows\n```json\n%s\n```\n' "$(jq '.diagnose' <<< "$ev" | head -c 8000)"
    printf '\nFull evidence: %s\n' "$ws/evidence-${job}-${d}.json"
  } > "$f"
  echo "$f"
}

# _render_plan <ws> <job-json> <date> <feature> <decision-json> <incident-path> -> plan path (template v2)
_render_plan() {
  local ws="$1" job="$2" d="$3" feature="$4" dec="$5" incident="$6" plan repo qr name
  name=$(jq -r .name <<< "$job"); repo=$(_expand_home "$(jq -r .owner_repo <<< "$job")")
  qr=$(jq -r '.quality_rules // ""' <<< "$job")
  plan="$ws/build-plan-${feature}.md"
  {
    printf '# Walkaway Build Plan: %s\n\n' "$feature"
    printf 'Template v2 (2026-11-12, merge-gate standard). Auto-generated by the walkaway job operator for the %s failure\non %s (incident: %s). The plan is the contract.\n\n' "$name" "$d" "$incident"
    printf '## Feature name\n`%s`\n\n## Branch name\n`feature/%s`\n\n## Repo\n`%s`\n\n' "$feature" "$feature" "$repo"
    printf '## Goal\n%s\n\n' "$(jq -r '.fix.goal // .fix.title' <<< "$dec")"
    printf '## Non-goals\n- Any other scheduled job, its schedule, or turning a job off.\n- Dashboards or new monitoring.\n\n'
    printf '## Evidence (do not re-derive)\n- Incident: %s (copied into handoff/ in Phase 0).\n' "$incident"
    printf -- '- Cause (job operator, read-only diagnosis): %s\n' "$(jq -r .cause <<< "$dec")"
    _md_list '.evidence' <<< "$dec"
    printf '\n## Decisions (who, when)\n- Jim 2026-11-13: failed scheduled jobs get an auto-fix build from template v2 (supervisor-v2-jobs). Protected actions unchanged.\n\n'
    printf '## Quality rules\n- Protocol "Merge-gate acceptance standard" applies in full.\n'
    [[ -n "$qr" ]] && printf -- '- Domain rules: %s (this job touches Showrunner lists: every rule there applies).\n' "$qr"
    printf -- '- "Fixed" means: the regression fixture built from this incident'"'"'s rows fails on the pre-fix commit and passes after. Live confirmation is NOT the builder'"'"'s job: after the merge the walkaway supervisor'"'"'s job watch re-checks %s read-only and reports OK.\n\n' "$name"
    printf '## Source of truth\n'
    jq -r '.check.queries | to_entries[] | "- \(.key): Supabase `\(.value | split("?")[0])` (read-only)"' <<< "$job"
    printf -- '- The incident rows archived in the incident file.\n\n'
    printf '## Acceptance criteria\n'
    jq -r '(.fix.acceptance_criteria // [])[] | "- [ ] \(.id) \(.text) (evidence: \(.evidence_file))"' <<< "$dec"
    printf -- '- [ ] ACR Regression fixture from this incident: %s. Fails on the pre-fix commit, passes now (evidence: handoff/%s-evidence/regression.txt).\n' "$(jq -r '.fix.regression_fixture // "the incident rows"' <<< "$dec")" "$feature"
    printf -- '- [ ] ACG Gates: the repo typecheck, lint, full test suite vs baseline, build; CI green; Codex closed (evidence: handoff/%s-evidence/MANIFEST.md).\n\n' "$feature"
    printf '## Gate checklist (the operator executes this before merge)\n- Open handoff/%s-evidence/MANIFEST.md; every AC maps to a file.\n- Re-run the regression fixture result; confirm fail-on-pre-fix / pass-now.\n- Trace the incident rows in the incident file to the fixture (all rows if fewer than 30).\n\n' "$feature"
    printf '## Escalate to Jim (never automatic)\n- Spend, credentials/logins/2FA, live writes to Audrey'"'"'s account or any publish/send, data deletion, schedule changes, anything marked "Jim decides".\n\n'
    printf '## Expected files touched\nExpected: %s files plus the handoff copies (plan, incident, evidence, reports). Hard ceiling: %s.\n' "$(jq -r '(.fix.files_expected // []) | length' <<< "$dec")" "$(( $(jq -r '(.fix.files_expected // []) | length' <<< "$dec") + 4 ))"
    _md_list '.fix.files_expected' <<< "$dec"
    printf '\n## Phases\n'
    printf '### Phase 0: Prepare\n- Copy %s, %s and this plan into handoff/ and commit them on the branch. Confirm the cause against the code.\n' "$incident" "$ws/evidence-${name}-${d}.json"
    printf '### Phase 1: Fix\n'
    _md_list '.fix.what_to_build' <<< "$dec"
    printf '### Phase 5: Tests\n- The regression fixture above (must fail on the pre-fix commit) + the full suite.\n'
    printf '### Phase 6: Smoke (read-only)\n- Re-run the fixed code path against fixtures and read-only queries only. Never trigger the job'"'"'s live action, never write to job data tables.\n'
    printf '### Phase 7: Codex review (cap 2), PR, CI, build report LAST (both files). Never merge.\n\n'
    printf '## Do NOT build\n- No changes to any other job, to schedules, or to job data rows.\n'
    _md_list '.fix.do_not_build' <<< "$dec"
    printf '\n## Stop rules (build-specific, in addition to WALKAWAY_BUILD_PROTOCOL.md)\n- Never write to job data tables or trigger the job'"'"'s live action during the build.\n'
    _md_list '.fix.stop_rules' <<< "$dec"
  } > "$plan"
  echo "$plan"
}

# _queue_or_launch <repo-root> <plan> <feature> -> one line describing what happened
_queue_or_launch() {
  local root="$1" plan="$2" feature="$3" key qfile active log t0
  key=$(registry_repo_key "$root"); qfile="$(queue_dir)/${key}.txt"
  mkdir -p "$(queue_dir)"
  grep -qxF "$plan" "$qfile" 2>/dev/null || echo "$plan" >> "$qfile"
  active=$(_other_active_build "$root" .repo_root)
  if [[ -n "$active" ]]; then
    echo "fix build $feature queued behind $active in $key"
    return 0
  fi
  local tmp="${qfile}.tmp.$$"
  awk -v n="$plan" '$0 != n' "$qfile" > "$tmp" && mv "$tmp" "$qfile"
  _sync_default "$root" > /dev/null
  log="${WALKAWAY_LAUNCH_LOG_DIR}/walkaway-${feature}.log"
  t0=$(date +%s)
  (cd "$root" || exit 1; nohup bash "$WALKAWAY_SH" "$plan" > "$log" 2>&1 < /dev/null &)
  for _ in $(seq 1 60); do
    registry_exists "$feature" && (( $(registry_get "$feature" .launched_epoch) >= t0 )) && break
    sleep 1
  done
  if registry_exists "$feature" && (( $(registry_get "$feature" .launched_epoch) >= t0 )); then
    echo "fix build $feature launched (builder pid $(registry_get "$feature" .builder_pid))"
  else
    echo "LAUNCH-FAILED fix build $feature did not register (see $log)"
  fi
}

# ── modes ────────────────────────────────────────────────────────────────────

jo_diagnose() {
  local job_name="$1" d="$2" cfg job ws ev dec decision protected live conf question forced="" incident
  cfg=$(jobs_config) || return 1
  job=$(jobs_get "$cfg" "$job_name")
  ws=$(_jo_ws "$job_name" "$d"); mkdir -p "$ws" "${WALKAWAY_HOME}/logs"
  local repo
  repo=$(_expand_home "$(jq -r .owner_repo <<< "$job")")

  # Evidence: the failing check + the diagnose queries/logs (read-only) + the job's state and config.
  ev=$(jq -cn --argjson c "$(jobs_check "$cfg" "$job_name" "$d")" --argjson g "$(jobs_diagnose "$cfg" "$job_name" "$d")" \
         --argjson s "$(cat "$(_jstate_file "$job_name")" 2>/dev/null || echo '{}')" --argjson j "$job" \
         '{job: $j, state: $s, check: $c, diagnose: $g}')
  echo "$ev" | jq . > "$ws/evidence-${job_name}-${d}.json"

  # One auto-fix build per job per day, and never a second one while an earlier fix is still in flight.
  local prev prev_state
  prev=$(jstate_get "$job_name" .fix_feature); prev_state=""
  [[ -n "$prev" ]] && prev_state=$(registry_get "$prev" .state)
  if [[ "$(jstate_get "$job_name" .fix_date)" == "$d" ]]; then
    forced="a fix build for $job_name already ran today ($prev)"
  elif [[ -n "$prev" && -n "$prev_state" && "$prev_state" != "MERGED" ]]; then
    jobs_transition "$job_name" FIXING "failed again; earlier fix build $prev still $prev_state"
    return 0
  fi

  if [[ -z "$forced" ]]; then
    local task
    task="MODE: JOB FAILURE DIAGNOSIS (read-only)

Job: $job_name ($(jq -r .title <<< "$job")), day $d
Owner repo (read its code; this is your working dir): $repo
Incident evidence JSON (check rows, diagnose rows, logs, jobs.yaml entry, day state): $ws/evidence-${job_name}-${d}.json
Job protected flag: $(jq -r .protected <<< "$job")
Quality rules file: $(jq -r '.quality_rules // "none"' <<< "$job")
Protocol: $WALKAWAY_PROTOCOL_PATH
Pointers: $(jq -r '(.diagnose.notes // []) | join(" | ")' <<< "$job")

Diagnose the failure from the evidence and the code. Decide fix (fill every fix field) or escalate (one question)."
    dec=$(_jask "$repo" "$ws" "$task")
  fi
  dec=${dec:-'{}'}
  decision=$(jq -r '.decision // ""' <<< "$dec")
  protected=$(jq -r 'if (.protected_hit | type) == "boolean" then .protected_hit else true end' <<< "$dec")
  live=$(jq -r 'if (.needs_live_action | type) == "boolean" then .needs_live_action else true end' <<< "$dec")
  conf=$(jq -r '.confidence // "low"' <<< "$dec"); question=$(jq -r '.question // ""' <<< "$dec")

  # Deterministic guards on top of the model.
  [[ -z "$forced" && -z "$decision" ]] && forced="diagnosis returned no decision"
  [[ -z "$forced" && "$protected" == "true" ]] && forced="protected action"
  [[ -z "$forced" && "$(jq -r .protected <<< "$job")" == "true" && "$live" == "true" ]] && forced="protected job: verifying the fix needs its live action"
  [[ -z "$forced" && "$decision" == "fix" && "$conf" != "high" ]] && forced="confidence $conf"
  [[ -z "$forced" && "$decision" == "fix" ]] && ! jq -e '(.fix.what_to_build // []) | length > 0' <<< "$dec" > /dev/null && forced="fix without what_to_build"

  if [[ "$decision" != "fix" || -n "$forced" ]]; then
    [[ -z "$question" ]] && question="$job_name failed $d ($(jstate_get "$job_name" .failed_detail | cut -c1-90)): ${forced:-cause unclear}. How should it be handled?"
    incident=$(_write_incident "$ws" "$job_name" "$d" "$dec" "$ev" "ESCALATED${forced:+ ($forced)}: $question")
    jstate_update "$job_name" '.incident = $i' --arg i "$incident"
    jobs_transition "$job_name" ESCALATED "$question"
    return 0
  fi

  local feature plan root outcome
  feature="fix-${job_name}-${d//-/}"
  incident=$(_write_incident "$ws" "$job_name" "$d" "$dec" "$ev" "FIX BUILD $feature (template v2 plan: $ws/build-plan-${feature}.md)")
  plan=$(_render_plan "$ws" "$job" "$d" "$feature" "$dec" "$incident")
  root=$repo
  outcome=$(_queue_or_launch "$root" "$plan" "$feature")
  jstate_update "$job_name" '.incident = $i | .fix_feature = $f | .fix_plan = $p | .fix_date = $d | .retry_ran = false' \
    --arg i "$incident" --arg f "$feature" --arg p "$plan" --arg d "$d"
  if [[ "$outcome" == LAUNCH-FAILED* ]]; then
    jobs_transition "$job_name" ESCALATED "${outcome#LAUNCH-FAILED }. Launch the fix for $job_name manually?"
    return 0
  fi
  jobs_transition "$job_name" FIXING "cause: $(jq -r .cause <<< "$dec" | cut -c1-120); $outcome"
}

jo_progress() {
  local job_name="$1" cfg job feature fstate cmd
  cfg=$(jobs_config) || return 1
  job=$(jobs_get "$cfg" "$job_name")
  feature=$(jstate_get "$job_name" .fix_feature)
  [[ -n "$feature" ]] || return 0
  if ! registry_exists "$feature"; then
    jstate_update "$job_name" '.last_action = $a' --arg a "fix build $feature queued (not launched yet)"
    return 0
  fi
  fstate=$(registry_get "$feature" .state)
  if [[ "$fstate" != "MERGED" ]]; then
    jstate_update "$job_name" '.last_action = $a' --arg a "fix build $feature $fstate"
    return 0
  fi
  [[ "$(jstate_get "$job_name" .retry_ran)" == "true" ]] && return 0
  jstate_update "$job_name" '.retry_ran = true'
  cmd=$(jq -r '.retry.command // ""' <<< "$job")
  if [[ -z "$cmd" || "$(jq -r .protected <<< "$job")" == "true" ]]; then
    jstate_update "$job_name" '.last_action = $a' --arg a "fix $feature merged; no safe retry path - confirming on the job's next run"
    return 0
  fi
  # The job's own documented retry path, once, bounded.
  local out rc=0 pid waited=0
  out="${WALKAWAY_HOME}/logs/job-retry-${job_name}.log"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] retry after $feature merged: $cmd" >> "$out"
  bash -c "$cmd" >> "$out" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    (( waited >= WALKAWAY_JOB_RETRY_TIMEOUT )) && { _kill_tree "$pid"; break; }
    sleep 1; waited=$((waited + 1))
  done
  wait "$pid" 2>/dev/null || rc=$?
  jstate_update "$job_name" '.last_action = $a' --arg a "fix $feature merged; retry path triggered (rc $rc); confirming OK"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  mode="${1:-}"; job_arg="${2:-}"; day_arg="${3:-}"
  [[ -n "$mode" && -n "$job_arg" ]] || { echo "Usage: job-operator.sh <diagnose|progress> <job> [date]" >&2; exit 1; }
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] job-operator $mode $job_arg ${day_arg}"
  case "$mode" in
    diagnose) jo_diagnose "$job_arg" "${day_arg:-$(jobs_today)}" ;;
    progress) jo_progress "$job_arg" ;;
    *) echo "job-operator: unknown mode $mode" >&2; exit 1 ;;
  esac
  [[ "$mode" == "diagnose" ]] && jstate_update "$job_arg" 'del(.operator_pid)'
fi
