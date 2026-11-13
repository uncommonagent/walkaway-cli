#!/usr/bin/env bash
# Walkaway operator: acts on a build the supervisor classified.
#
#   operator.sh resume     <feature> <reason>     DIED/STALLED: kill leftovers, auto RESUME DIRECTIVE, relaunch (cap 2)
#   operator.sh triage     <feature>              STOPPED: headless claude decides approve-and-relaunch vs ESCALATE
#   operator.sh gate       <feature>              DONE: headless claude verifies evidence; PASS merges, FAIL rejects (cap 2)
#   operator.sh post-merge <feature> <reason>     MERGED: kill builder + watcher, launch the repo's next queued plan
#   operator.sh escalate   <feature> <question>   ESCALATED: one question to Jim (ntfy priority high), then wait
#
# Judgment (triage, gate) comes from `claude -p` with templates/operator-prompt.md as a fixed system
# prompt and a JSON schema for the decision. Every action (kill, directive, relaunch, merge) is done
# here in shell, never by the model. Every decision is appended to handoff/operator-log-<feature>.md
# and committed (the MERGED outcome, which happens after the checkout is cleaned up, goes to
# $WALKAWAY_HOME/logs/operator-<feature>.log + registry + ntfy instead).

set -uo pipefail

OP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/registry.sh
source "${OP_DIR}/registry.sh"
# shellcheck source=lib/notify.sh
source "${OP_DIR}/notify.sh"
# shellcheck source=lib/supervisor.sh
source "${OP_DIR}/supervisor.sh"

WALKAWAY_SH="${WALKAWAY_SH:-${OP_DIR}/../walkaway.sh}"
WALKAWAY_OPERATOR_CMD="${WALKAWAY_OPERATOR_CMD:-claude}"
WALKAWAY_OPERATOR_PROMPT="${WALKAWAY_OPERATOR_PROMPT:-${OP_DIR}/../templates/operator-prompt.md}"
WALKAWAY_OPERATOR_TIMEOUT="${WALKAWAY_OPERATOR_TIMEOUT:-2400}"
WALKAWAY_PROTOCOL_PATH="${WALKAWAY_PROTOCOL_PATH:-$HOME/Projects/BPO/bpo-comp-tool/handoff/WALKAWAY_BUILD_PROTOCOL.md}"
WALKAWAY_MERGE_CHECK_WAIT="${WALKAWAY_MERGE_CHECK_WAIT:-900}"
WALKAWAY_MERGE_CHECK_POLL="${WALKAWAY_MERGE_CHECK_POLL:-30}"
WALKAWAY_MERGE_EMPTY_CHECKS_GRACE="${WALKAWAY_MERGE_EMPTY_CHECKS_GRACE:-120}"
WALKAWAY_LAUNCH_LOG_DIR="${WALKAWAY_LAUNCH_LOG_DIR:-/tmp}"
RESUME_CAP=2
REJECTION_CAP=2
APPROVAL_CAP=3

_et() { TZ=America/New_York date '+%Y-%m-%d %H:%M ET'; }
_reg() { registry_get "$FEATURE" "$1"; }

# ── operator log + directives ────────────────────────────────────────────────

_oplog_path() { echo "$(_reg .repo)/handoff/operator-log-${FEATURE}.md"; }

# _oplog <decision-title> <body>
_oplog() {
  local path
  path=$(_oplog_path)
  mkdir -p "$(dirname "$path")"
  [[ -f "$path" ]] || printf '# Operator log - %s\n\nEvery supervisor/operator decision for this build, newest last.\n' "$FEATURE" > "$path"
  printf '\n## %s - %s\n%s\n' "$(_et)" "$1" "$2" >> "$path"
}

# Insert "## RESUME DIRECTIVE (...) - read first" directly under the plan's title line (house convention).
_write_directive() {
  local title="$1" body="$2" plan tmp
  plan=$(_reg .plan)
  tmp="${plan}.tmp.$$"
  # Multi-line bodies (every model-written directive) must survive intact: no awk -v (rejects newlines).
  {
    head -n 1 "$plan"
    printf '\n## RESUME DIRECTIVE (%s, %s) - read first\n%s\n' "$title" "$(_et)" "$body"
    tail -n +2 "$plan"
  } > "$tmp" && mv "$tmp" "$plan" || { rm -f "$tmp"; return 1; }
}

# Commit only the operator log (and plan, when it lives in the same work tree). Never sweeps up builder work.
# Returns the repo commit's status: the merge gate must not merge a PASS it could not commit.
_commit_decision() {
  local msg="$1" repo plan plan_dir paths=()
  repo=$(_reg .repo); plan=$(_reg .plan)
  paths+=("$(_oplog_path)")
  [[ -f "$repo/handoff/gate-${FEATURE}.md" ]] && paths+=("$repo/handoff/gate-${FEATURE}.md")
  plan_dir=$(git -C "$(dirname "$plan")" rev-parse --show-toplevel 2>/dev/null || true)
  if [[ "$plan_dir" == "$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" ]]; then
    paths+=("$plan")
  elif [[ -n "$plan_dir" ]] && ! git -C "$plan_dir" diff --quiet -- "$plan" 2>/dev/null; then
    git -C "$plan_dir" add -- "$plan" && git -C "$plan_dir" commit -q --no-verify -m "operator: $FEATURE: $msg" -- "$plan" || true
  fi
  git -C "$repo" add -- "${paths[@]}" 2>/dev/null || true
  git -C "$repo" commit -q --no-verify -m "operator: $FEATURE: $msg" -- "${paths[@]}" 2>&1
}

# ── process control ──────────────────────────────────────────────────────────

_kill_tree() {
  local pid="$1" child
  for child in $(pgrep -P "$pid" 2>/dev/null); do _kill_tree "$child"; done
  kill -TERM "$pid" 2>/dev/null || true
}

# Kill this build's builder (only if the recorded PID is still the same process) and its watcher.
_kill_leftovers() {
  local pid started wpid
  pid=$(_reg .builder_pid); started=$(_reg .builder_started); wpid=$(_reg .watcher_pid)
  if pid_alive "$pid" "$started"; then
    _kill_tree "$pid"
    for _ in 1 2 3 4 5; do pid_alive "$pid" "$started" || break; sleep 1; done
    pid_alive "$pid" "$started" && kill -KILL "$pid" 2>/dev/null
  fi
  if [[ -n "$wpid" ]] && ps -o command= -p "$wpid" 2>/dev/null | grep -q 'watcher.sh'; then
    kill "$wpid" 2>/dev/null || true
  fi
  rm -f "${WALKAWAY_HOME}/state/watcher-${FEATURE}.json" "${WALKAWAY_HOME}/state/.watcher-state-${FEATURE}"
}

# Relaunch via walkaway (which re-registers: new PIDs, launched_at, launch_count+1). Echoes the new builder PID.
_relaunch() {
  local plan repo prev log args=(--force)
  plan=$(_reg .plan); repo=$(_reg .repo_root); prev=$(_reg .launch_count)
  [[ "$(_reg .worktree)" == "true" ]] && args+=(--worktree)
  log="${WALKAWAY_LAUNCH_LOG_DIR}/walkaway-${FEATURE}-auto-$((prev + 1)).log"
  (cd "$repo" || exit 1; nohup bash "$WALKAWAY_SH" "${args[@]}" "$plan" > "$log" 2>&1 < /dev/null &)
  for _ in $(seq 1 60); do
    [[ "$(_reg .launch_count)" -gt "$prev" ]] && { _reg .builder_pid; return 0; }
    sleep 1
  done
  echo "relaunch did not register within 60s; see $log" >&2
  return 1
}

# ── claude -p decisions ──────────────────────────────────────────────────────

# _ask <task-prompt> <json-schema>  -> structured decision JSON on stdout (empty on failure/timeout)
_ask() {
  local task="$1" schema="$2" repo out
  repo=$(_reg .repo)
  out=$(mktemp)
  (
    cd "$repo" && "$WALKAWAY_OPERATOR_CMD" -p "$task" \
      --append-system-prompt-file "$WALKAWAY_OPERATOR_PROMPT" \
      --output-format json --json-schema "$schema" --no-session-persistence \
      --add-dir "$(dirname "$WALKAWAY_PROTOCOL_PATH")" --add-dir "$(dirname "$(_reg .plan)")" \
      --allowedTools Read Glob Grep \
        "Bash(gh pr view:*)" "Bash(gh pr checks:*)" "Bash(gh pr diff:*)" \
        "Bash(git log:*)" "Bash(git show:*)" "Bash(git diff:*)" "Bash(git status:*)" \
        "Bash(jq:*)" "Bash(ls:*)" "Bash(wc:*)" "Bash(head:*)" "Bash(tail:*)" "Bash(cat:*)" "Bash(find:*)" \
      --disallowedTools Edit Write NotebookEdit "Bash(gh pr merge:*)" "Bash(git push:*)" "Bash(git commit:*)" "Bash(rm:*)"
  ) > "$out" 2>>"${WALKAWAY_HOME}/logs/operator-${FEATURE}.stderr.log" &
  local cpid=$! waited=0
  while kill -0 "$cpid" 2>/dev/null; do
    if (( waited >= WALKAWAY_OPERATOR_TIMEOUT )); then _kill_tree "$cpid"; break; fi
    sleep 5; waited=$((waited + 5))
  done
  wait "$cpid" 2>/dev/null
  jq -c '.structured_output // empty' "$out" 2>/dev/null
  rm -f "$out"
}

_context_block() {
  cat <<EOF
Feature: $FEATURE
Repo (build work tree): $(_reg .repo)
Branch: $(_reg .branch)
Plan (the contract): $(_reg .plan)
Protocol: $WALKAWAY_PROTOCOL_PATH
Build log: $(_reg .repo)/handoff/build-log-${FEATURE}.md
Operator log (earlier decisions): $(_oplog_path)
Counters: resume_count=$(_reg .resume_count) gate_rejections=$(_reg .gate_rejections) approvals=$(_reg .approvals)
EOF
}

# ── modes ────────────────────────────────────────────────────────────────────

op_escalate() {
  local question="$1"
  _oplog "ESCALATED" "Question for Jim: $question"
  _commit_decision "escalated"
  supervisor_transition "$FEATURE" ESCALATED "$question" high
}

op_resume() {
  local reason="$1" n
  n=$(_reg .resume_count)
  if (( n >= RESUME_CAP )); then
    _kill_leftovers
    op_escalate "Builder ${reason%%:*} again after ${RESUME_CAP} auto-resumes ($reason). Relaunch it, or stop this build?"
    return 0
  fi
  n=$((n + 1))
  _kill_leftovers
  registry_update "$FEATURE" '.resume_count = ($n|tonumber)' --arg n "$n"
  local baseline
  baseline=$(_reg .report_baseline); baseline=${baseline:-$(_reg .launched_epoch)}
  _write_directive "auto, resume $n/$RESUME_CAP" "The previous builder session ended without a build or failure report ($reason). Continue from handoff/build-log-${FEATURE}.md and the newest phase report: do NOT redo committed phases; finish the first unfinished phase, then continue the plan. Any earlier RESUME DIRECTIVE not marked [DONE] still applies.
No-op resume: if every phase is already committed and handoff/build-report-${FEATURE}.md exists, re-run nothing. Append one line \"build-report ${FEATURE} (no-op resume $n/$RESUME_CAP, <ET timestamp>): all phases already complete\" to handoff/build-report-${FEATURE}.md (and build-report-CURRENT.md), commit and push it, then exit."
  _oplog "RESUME (auto $n/$RESUME_CAP)" "Trigger: $reason. Killed leftovers, wrote RESUME DIRECTIVE (auto) to the plan, relaunching."
  _commit_decision "auto-resume $n/$RESUME_CAP"
  local newpid
  if newpid=$(_relaunch); then
    # A resume continues the same build: keep the report baseline of the launch it resumes.
    registry_update "$FEATURE" '.last_action = $a | .report_baseline = ($b|tonumber)' \
      --arg a "auto-resume $n/$RESUME_CAP relaunched (builder pid $newpid)" --arg b "$baseline"
  else
    op_escalate "Auto-resume relaunch failed for $FEATURE (see ${WALKAWAY_LAUNCH_LOG_DIR}/walkaway-${FEATURE}-auto-*.log). Relaunch manually?"
  fi
}

_newest_failure_report() {
  local r
  r=$(supervisor_failure_report "$(_reg .repo)" "$FEATURE")
  [[ -n "$r" ]] && echo "${r#*$'\t'}"
  return 0
}

TRIAGE_SCHEMA='{"type":"object","properties":{
 "decision":{"type":"string","enum":["approve","escalate"]},
 "protected_hit":{"type":"boolean","description":"true if the fix or the stop touches ANY protected action"},
 "in_scope":{"type":"boolean"},
 "directive":{"type":"string","description":"approve: the full approving RESUME DIRECTIVE body (fix as proposed plus obvious additions)"},
 "question":{"type":"string","description":"escalate: ONE specific question for Jim, one line"},
 "rationale":{"type":"string"}},
 "required":["decision","protected_hit","in_scope","rationale"]}'

op_triage() {
  local report checks_note="" n
  report=$(_newest_failure_report)
  local launched rm=0
  launched=$(_reg .launched_epoch)
  [[ -n "$report" ]] && rm=$(stat -f %m "$report")
  if [[ -z "$report" ]] || (( rm <= launched )); then
    if [[ "$(supervisor_pr_json "$(_reg .repo)" "$(_reg .branch)" | jq -r '.state // ""')" == "OPEN" ]]; then
      report="(none - the build report was written but PR checks FAILED)"
      checks_note="Build report: $(_reg .repo)/handoff/build-report-${FEATURE}.md. Inspect the failing checks with gh pr checks."
    else
      report="(none - the build report is committed at the branch head but no PR is open and the builder exited)"
      checks_note="Build report: $(_reg .repo)/handoff/build-report-${FEATURE}.md. Phase 8 opens the PR before the report; decide whether to approve opening it."
    fi
  fi
  n=$(_reg .approvals)
  if (( n >= APPROVAL_CAP )); then
    op_escalate "$FEATURE stopped again after $APPROVAL_CAP auto-approved fixes ($(basename "$report")). Decide the next fix?"
    return 0
  fi

  local task decision
  task="MODE: STOPPED TRIAGE

$(_context_block)
Failure report: $report
$checks_note

Read the protocol, the plan, the build log, the failure report and the operator log. Decide per your
operating standard: approve (write the approving directive) or escalate (one question)."
  decision=$(_ask "$task" "$TRIAGE_SCHEMA")

  local d protected in_scope directive question rationale
  d=$(jq -r '.decision // ""' <<< "$decision"); protected=$(jq -r 'if (.protected_hit | type) == "boolean" then .protected_hit else true end' <<< "$decision")
  in_scope=$(jq -r '.in_scope // false' <<< "$decision"); directive=$(jq -r '.directive // ""' <<< "$decision")
  question=$(jq -r '.question // ""' <<< "$decision"); rationale=$(jq -r '.rationale // ""' <<< "$decision")

  # Deterministic guards on top of the model: protected/out-of-scope/"Jim decides" never auto-approve.
  local forced=""
  [[ -z "$d" ]] && forced="operator returned no decision"
  [[ "$protected" == "true" ]] && forced="protected action"
  [[ "$in_scope" != "true" ]] && forced="${forced:-out of plan scope}"
  if [[ -f "$report" ]] && grep -qi 'jim decides' "$report"; then forced="report marks 'Jim decides'"; fi
  [[ "$d" == "approve" && -z "$directive" ]] && forced="${forced:-approve without a directive}"

  if [[ "$d" != "approve" || -n "$forced" ]]; then
    [[ -z "$question" ]] && question="$FEATURE stopped ($(basename "$report")): ${forced:-operator escalated}. How should it proceed?"
    _oplog "TRIAGE: ESCALATE${forced:+ ($forced)}" "Report: $report
Rationale: $rationale
Decision JSON: \`$decision\`"
    op_escalate "$question"
    return 0
  fi

  n=$((n + 1))
  _kill_leftovers
  registry_update "$FEATURE" '.approvals = ($n|tonumber)' --arg n "$n"
  _write_directive "auto, approved fix $n" "$directive"
  _oplog "TRIAGE: APPROVE ($n/$APPROVAL_CAP)" "Report: $report
Rationale: $rationale
Directive written to the plan:
$directive"
  _commit_decision "approved fix $n for $(basename "$report")"
  local newpid
  if newpid=$(_relaunch); then
    registry_update "$FEATURE" '.last_action = $a' --arg a "approved fix $n, relaunched (builder pid $newpid)"
  else
    op_escalate "Relaunch after approved fix failed for $FEATURE (see ${WALKAWAY_LAUNCH_LOG_DIR}/walkaway-${FEATURE}-auto-*.log). Relaunch manually?"
  fi
}

GATE_SCHEMA='{"type":"object","properties":{
 "verdict":{"type":"string","enum":["PASS","FAIL","ESCALATE"]},
 "criteria":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"met":{"type":"boolean"},"evidence":{"type":"string"}},"required":["id","met","evidence"]}},
 "screenshots_opened":{"type":"integer"},
 "json_files_parsed":{"type":"integer"},
 "rows_spot_checked":{"type":"integer"},
 "ci_green":{"type":"boolean"},
 "codex_closed":{"type":"boolean"},
 "findings":{"type":"array","items":{"type":"string"}},
 "directive":{"type":"string","description":"FAIL: the merge-gate rejection directive body with the exact findings and fixes"},
 "question":{"type":"string","description":"ESCALATE: ONE specific question for Jim"}},
 "required":["verdict","criteria","ci_green","codex_closed","findings"]}'

_pr_number() { supervisor_pr_json "$(_reg .repo)" "$(_reg .branch)" | jq -r '.number // empty'; }

# _wait_checks_green <sha>: wait for the PR's checks ON THE PUSHED GATE COMMIT to be green. Fails closed:
#  - a lookup that does not return this branch's OPEN PR is a lookup failure (gh error -> "{}" would otherwise
#    read as "no checks = green"); 3 in a row -> 1, so the caller escalates instead of merging unverified;
#  - a valid lookup whose headRefOid is not <sha> is GitHub still showing the previous head (and its old,
#    possibly green rollup): pending, never green;
#  - an empty rollup on <sha> is pending for WALKAWAY_MERGE_EMPTY_CHECKS_GRACE (checks not registered yet),
#    then green (a repo with no CI can still merge).
# Sets WAIT_REASON for the caller's escalation.
_wait_checks_green() {
  local sha="$1" c pr lookup_fails=0 v now deadline empty_since=0
  deadline=$(( $(date +%s) + WALKAWAY_MERGE_CHECK_WAIT ))
  WAIT_REASON="checks still pending after ${WALKAWAY_MERGE_CHECK_WAIT}s"
  while :; do
    pr=$(supervisor_pr_json "$(_reg .repo)" "$(_reg .branch)")
    v=$(jq -r --arg sha "$sha" 'if .number == null or .state != "OPEN" then "bad"
      elif .headRefOid != $sha then "stale" elif (.statusCheckRollup // []) == [] then "empty" else "ok" end' <<< "$pr" 2>/dev/null)
    now=$(date +%s)
    case "$v" in
      ok|empty|stale) lookup_fails=0 ;;
      *) lookup_fails=$((lookup_fails + 1))
         (( lookup_fails >= 3 )) && { WAIT_REASON="PR lookup failed 3 times"; return 1; } ;;
    esac
    case "$v" in
      stale) WAIT_REASON="PR head never reached the gate commit ${sha:0:7} within ${WALKAWAY_MERGE_CHECK_WAIT}s" ;;
      empty)
        (( empty_since == 0 )) && empty_since=$now
        (( now - empty_since >= WALKAWAY_MERGE_EMPTY_CHECKS_GRACE )) && return 0
        WAIT_REASON="no checks registered on ${sha:0:7}" ;;
      ok)
        c=$(supervisor_checks "$pr")
        [[ "$c" == "green" ]] && return 0
        [[ "$c" == "failed" ]] && { WAIT_REASON="checks failed on ${sha:0:7}"; return 1; } ;;
    esac
    (( now >= deadline )) && return 1
    sleep "$WALKAWAY_MERGE_CHECK_POLL"
  done
}

_is_worktree() { [[ "$(_reg .repo)" != "$(_reg .repo_root)" ]]; }

_prune_worktree() {
  local repo root
  repo=$(_reg .repo); root=$(_reg .repo_root)
  [[ "$repo" != "$root" && -d "$repo" ]] || return 0
  git -C "$root" worktree remove --force "$repo" 2>/dev/null || true
  git -C "$root" worktree prune 2>/dev/null || true
}

op_gate() {
  local pr n
  pr=$(_pr_number)
  local task decision
  task="MODE: MERGE GATE

$(_context_block)
PR: #$pr (gh pr view $pr)
Supervisor-observed PR state + checks (gh pr view --json): $(supervisor_pr_json "$(_reg .repo)" "$(_reg .branch)" | jq -c '{number,state,mergeStateStatus,statusCheckRollup}')
Build report: $(_reg .repo)/handoff/build-report-${FEATURE}.md

Verify every acceptance criterion in the plan against the ARCHIVED evidence yourself, per your operating
standard (open every screenshot, parse audit/summary JSON, spot-check >= 10 data rows against source data,
confirm CI green and Codex closed)."
  decision=$(_ask "$task" "$GATE_SCHEMA")

  local verdict findings directive question
  verdict=$(jq -r '.verdict // ""' <<< "$decision")
  findings=$(jq -r '(.findings // []) | map("- " + .) | join("\n")' <<< "$decision")
  directive=$(jq -r '.directive // ""' <<< "$decision"); question=$(jq -r '.question // ""' <<< "$decision")
  local criteria
  criteria=$(jq -r '(.criteria // []) | map("- " + .id + ": " + (if .met then "MET" else "NOT MET" end) + " - " + .evidence) | join("\n")' <<< "$decision")
  local unmet
  unmet=$(jq -r '[(.criteria // [])[] | select(.met | not)] | length' <<< "$decision" 2>/dev/null || echo 1)
  [[ "$verdict" == "PASS" && ( "$unmet" != "0" || "$(jq -r '.ci_green' <<< "$decision")" != "true" ||
       "$(jq -r '.codex_closed' <<< "$decision")" != "true" ) ]] && verdict="FAIL"
  [[ -z "$verdict" ]] && { op_escalate "Merge-gate operator returned no verdict for $FEATURE PR #$pr. Review manually?"; return 0; }

  local summary
  summary="Verdict: $verdict (screenshots opened: $(jq -r '.screenshots_opened // 0' <<< "$decision"), JSON parsed: $(jq -r '.json_files_parsed // 0' <<< "$decision"), rows spot-checked: $(jq -r '.rows_spot_checked // 0' <<< "$decision"), CI green: $(jq -r '.ci_green' <<< "$decision"), Codex closed: $(jq -r '.codex_closed' <<< "$decision"))
Criteria:
$criteria
Findings:
$findings"
  # Protocol "Merge-gate acceptance standard" rule 10: gate-<feature>.md with PASS/FAIL per AC + evidence read.
  printf '# Merge gate - %s (PR #%s, %s)\n\n%s\n' "$FEATURE" "$pr" "$(_et)" "$summary" > "$(_reg .repo)/handoff/gate-${FEATURE}.md"

  case "$verdict" in
    PASS)
      _oplog "MERGE GATE: PASS (PR #$pr)" "$summary"
      # The PASS decision must be in the PR before anything merges: a failed commit or push escalates.
      local push_out sha
      if ! push_out=$(_commit_decision "merge gate PASS") ||
         ! push_out=$(git -C "$(_reg .repo)" push -q origin "$(_reg .branch)" 2>&1); then
        op_escalate "Merge gate PASS for $FEATURE could not be pushed ($(echo "${push_out:-commit failed}" | tail -1 | cut -c1-160)). Push/merge manually?"
        return 0
      fi
      sha=$(git -C "$(_reg .repo)" rev-parse HEAD)
      if ! _wait_checks_green "$sha"; then
        op_escalate "Merge gate passed for $FEATURE but PR #$pr checks are not green after the gate push ($WAIT_REASON). Merge anyway?"
        return 0
      fi
      _kill_leftovers
      # Nothing is removed before the merge succeeds: a failed merge escalates into the intact checkout.
      # A worktree build's branch is checked out in the worktree, so gh cannot delete it; we do that after.
      local merge_out root branch merge_args=(--squash --delete-branch)
      root=$(_reg .repo_root); branch=$(_reg .branch)
      _is_worktree && merge_args=(--squash)
      if ! merge_out=$(cd "$root" && "$WALKAWAY_GH_CMD" pr merge "$pr" "${merge_args[@]}" 2>&1); then
        op_escalate "gh pr merge failed for $FEATURE PR #$pr: $(echo "$merge_out" | tail -1 | cut -c1-160). Merge manually?"
        return 0
      fi
      if _is_worktree; then
        _prune_worktree
        git -C "$root" push -q origin --delete "$branch" 2>/dev/null || true
        git -C "$root" branch -q -D "$branch" 2>/dev/null || true
      fi
      op_post_merge "PR #$pr squash-merged by merge gate"
      ;;
    FAIL)
      n=$(_reg .gate_rejections)
      if (( n >= REJECTION_CAP )); then
        _oplog "MERGE GATE: FAIL (cap reached)" "$summary"
        op_escalate "$FEATURE failed the merge gate a third time (PR #$pr): $(jq -r '(.findings // ["see operator log"])[0]' <<< "$decision" | cut -c1-160). Accept, or what fix?"
        return 0
      fi
      n=$((n + 1))
      [[ -z "$directive" ]] && directive="Merge-gate rejection. Fix every finding below, re-archive the evidence, re-run the smoke, update the build report (written LAST).
$findings"
      _kill_leftovers
      registry_update "$FEATURE" '.gate_rejections = ($n|tonumber)' --arg n "$n"
      _write_directive "auto, merge-gate rejection $n/$REJECTION_CAP" "$directive"
      _oplog "MERGE GATE: FAIL -> rejection directive $n/$REJECTION_CAP (PR #$pr)" "$summary"
      _commit_decision "merge-gate rejection $n/$REJECTION_CAP"
      local newpid
      if newpid=$(_relaunch); then
        registry_update "$FEATURE" '.last_action = $a' --arg a "merge-gate rejection $n/$REJECTION_CAP, relaunched (builder pid $newpid)"
      else
        op_escalate "Relaunch after merge-gate rejection failed for $FEATURE. Relaunch manually?"
      fi
      ;;
    *)
      _oplog "MERGE GATE: ESCALATE (PR #$pr)" "$summary"
      op_escalate "${question:-Merge gate for $FEATURE PR #$pr is uncertain. Review the operator log and decide?}"
      ;;
  esac
}

# _other_active_build <root> <field>: the first other registered, non-MERGED build whose <field> is <root>.
#   .repo      -> a builder working in the root checkout itself (its branch must not be switched under it)
#   .repo_root -> any builder in this repository, root or worktree (one builder per repo)
_other_active_build() {
  local root="$1" field="$2" feature
  while IFS= read -r feature; do
    [[ -z "$feature" || "$feature" == "$FEATURE" ]] && continue
    [[ "$(registry_get "$feature" "$field")" == "$root" ]] || continue
    [[ "$(registry_get "$feature" .state)" == "MERGED" ]] && continue
    echo "$feature"; return 0
  done < <(registry_list)
}

# After a merge, put the repo on its freshly pulled default branch (queue launches need it for walkaway's base
# guard; walkaway-cli itself runs the supervisor from its working tree). A dirty tree is left alone. If another
# build is active in the root checkout, only remote refs are updated (echoes why).
_sync_default() {
  local root="$1" default active
  active=$(_other_active_build "$root" .repo)
  if [[ -n "$active" ]]; then
    git -C "$root" fetch -q origin 2>/dev/null || true
    echo "default-branch sync deferred: $active active in root"
    return 0
  fi
  default=$(git -C "$root" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
  default=${default:-main}
  git -C "$root" checkout -q "$default" 2>/dev/null && git -C "$root" pull -q --ff-only origin "$default" 2>/dev/null || true
}

# Launch the repo's next queued plan (one builder per repo). Echoes the launched feature, if any.
_launch_next() {
  local root key qfile next active
  root=$(_reg .repo_root); key=$(registry_repo_key "$root")
  qfile="$(queue_dir)/${key}.txt"
  [[ -f "$qfile" ]] || return 0
  next=$(grep -v '^[[:space:]]*\(#\|$\)' "$qfile" | head -1 || true)
  [[ -n "$next" ]] || return 0
  active=$(_other_active_build "$root" .repo_root)
  if [[ -n "$active" ]]; then
    echo "queued $(basename "$next") held: $active still active in $key"
    return 0
  fi
  if [[ ! -f "$next" ]]; then
    echo "queued plan missing: $next"
    return 0
  fi
  # Remove it from the queue first so a failing launch never relaunches in a loop.
  local tmp="${qfile}.tmp.$$"
  awk -v n="$next" 'done || $0 != n { print; next } { done = 1 }' "$qfile" > "$tmp" && mv "$tmp" "$qfile"
  _sync_default "$root"
  local nfeature log
  nfeature=$(bash "${OP_DIR}/parse-plan.sh" "$next" 2>/dev/null | sed -n 's/^FEATURE_NAME=//p')
  log="${WALKAWAY_LAUNCH_LOG_DIR}/walkaway-${nfeature:-next}.log"
  local t0
  t0=$(date +%s)
  (cd "$root" || exit 1; nohup bash "$WALKAWAY_SH" "$next" > "$log" 2>&1 < /dev/null &)
  _launched_since() { registry_exists "$nfeature" && (( $(registry_get "$nfeature" .launched_epoch) >= t0 )); }
  for _ in $(seq 1 60); do _launched_since && break; sleep 1; done
  if _launched_since; then
    echo "launched next: $nfeature (builder pid $(registry_get "$nfeature" .builder_pid))"
  else
    echo "next plan $(basename "$next") failed to launch (see $log)"
  fi
}

# The MERGED outcome goes to the operator log under $WALKAWAY_HOME, the registry and ntfy only: the build's
# checkout is gone or back on the default branch (or the next feature's), so nothing is written into a repo.
op_post_merge() {
  local reason="$1" next sync
  _kill_leftovers
  _prune_worktree
  sync=$(_sync_default "$(_reg .repo_root)")
  next=$(_launch_next)
  mkdir -p "${WALKAWAY_HOME}/logs"
  printf '[%s] MERGED: %s. %s%s\n' "$(_et)" "$reason" "${sync:+$sync. }" "${next:-No queued plan for this repo.}" >> "${WALKAWAY_HOME}/logs/operator-${FEATURE}.log"
  supervisor_transition "$FEATURE" MERGED "$reason; ${next:-queue empty}"
}

# ── entry ────────────────────────────────────────────────────────────────────

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  MODE="${1:-}"; FEATURE="${2:-}"
  [[ -n "$MODE" && -n "$FEATURE" ]] || { echo "Usage: operator.sh <resume|triage|gate|post-merge|escalate> <feature> [arg]" >&2; exit 1; }
  registry_exists "$FEATURE" || { echo "operator: $FEATURE not registered" >&2; exit 1; }
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] operator $MODE $FEATURE"
  case "$MODE" in
    resume)     op_resume "${3:-DIED}" ;;
    triage)     op_triage ;;
    gate)       op_gate ;;
    post-merge) op_post_merge "${3:-PR merged}" ;;
    escalate)   op_escalate "${3:-Operator needs a decision on $FEATURE.}" ;;
    *) echo "operator: unknown mode $MODE" >&2; exit 1 ;;
  esac
  registry_update "$FEATURE" '.operator_pid = null'
fi
