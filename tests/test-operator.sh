#!/usr/bin/env bash
# Operator + transition tests in a scratch world: real walkaway launches, real stub-builder processes,
# real supervisor ticks; claude -p replaced by a stub that returns canned decisions, gh by gh-sim, ntfy
# recorded to ntfy.log only (WALKAWAY_NTFY_DISABLED=1). Exit 0 = all pass.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/.."
# shellcheck source=tests/drill/scratch.sh
source "${SCRIPT_DIR}/drill/scratch.sh"

W=$(mktemp -d)
export WALKAWAY_HOME="$W/home" GH_SIM_DIR="$W/gh" WALKAWAY_LAUNCH_LOG_DIR="$W/logs"
export WALKAWAY_BUILDER_CMD="${SCRIPT_DIR}/drill/stub-builder.sh" WALKAWAY_GH_CMD="${SCRIPT_DIR}/drill/gh-sim.sh"
export WALKAWAY_OPERATOR_CMD="$W/stub-claude" WALKAWAY_NTFY_DISABLED=1 WALKAWAY_CLAUDE_PROJECTS="$W/none"
export WALKAWAY_MERGE_CHECK_WAIT=30 NTFY_TOPIC=test-topic
mkdir -p "$WALKAWAY_HOME/queue" "$WALKAWAY_LAUNCH_LOG_DIR" "$W/decisions"
touch "$WALKAWAY_HOME/supervisor.enabled"

# claude stub: returns $W/decisions/<feature>.json as structured_output
cat > "$W/stub-claude" <<EOF
#!/usr/bin/env bash
feature=\$(printf '%s\n' "\$2" | sed -n 's/^Feature: //p' | head -1)
echo "\$(date +%T) stub-claude \$feature" >> "$W/stub-claude.log"
jq -c '{structured_output: .}' "$W/decisions/\$feature.json"
EOF
chmod +x "$W/stub-claude"

PASS=0
FAIL=0
check() { # label condition...
  local label="$1"; shift
  if "$@"; then echo "  PASS: $label"; PASS=$((PASS + 1)); else echo "  FAIL: $label"; FAIL=$((FAIL + 1)); fi
}
reg() { jq -r "$2 // empty" "$WALKAWAY_HOME/registry/$1.json"; }
ntfy_count() { grep -c "	$1\$" "$WALKAWAY_HOME/logs/ntfy.log" 2>/dev/null || true; }
tick() { bash "$ROOT/lib/supervisor.sh" tick >> "$W/supervisor.log" 2>&1; }
wait_operator() { # feature
  local i p
  for i in $(seq 1 60); do
    p=$(reg "$1" .operator_pid)
    { [[ -z "$p" ]] || ! kill -0 "$p" 2>/dev/null; } && return 0
    sleep 1
  done
}
launch() { # repo feature
  (cd "$1" || exit 1; nohup bash "$ROOT/walkaway.sh" "$1/handoff/build-plan-$2.md" > "$W/logs/walkaway-$2.log" 2>&1 < /dev/null &)
  local i
  for i in $(seq 1 30); do [[ -f "$WALKAWAY_HOME/registry/$2.json" ]] && return 0; sleep 1; done
}
kill_builder() { kill "$(reg "$1" .builder_pid)"; sleep 1; }

cleanup() {
  local f p
  for f in "$WALKAWAY_HOME"/registry/*.json; do
    [[ -f "$f" ]] || continue
    for p in $(jq -r '.builder_pid, .watcher_pid | select(. != null)' "$f"); do
      pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null
    done
  done
  [[ -n "${KEEP_WORK:-}" ]] && echo "kept $W" || rm -rf "$W"
}
trap cleanup EXIT

# ── T1/T2: RUNNING notifies once; DIED -> auto-resume; cap 2 -> ESCALATED ─────
echo "T1/T2 resume flow"
R1=$(drill_make_repo "$W/repos" r1 t-run)
drill_set_modes "$R1" t-run work
launch "$R1" t-run
sleep 2; tick; tick
check "RUNNING notified exactly once over 2 ticks" [ "$(ntfy_count 't-run: RUNNING - builder pid [0-9]*, active 0m ago')" -eq 1 ]
kill_builder t-run; tick
check "DIED notified once" [ "$(grep -c 't-run: DIED - ' "$WALKAWAY_HOME/logs/ntfy.log")" -eq 1 ]
check "relaunched (launch_count 2, resume_count 1)" [ "$(reg t-run .launch_count)/$(reg t-run .resume_count)" == "2/1" ]
check "auto RESUME DIRECTIVE written under plan title" grep -q '^## RESUME DIRECTIVE (auto, resume 1/2' "$R1/handoff/build-plan-t-run.md"
check "operator log committed" bash -c "git -C '$R1' log -1 --format=%s | grep -q 'operator: t-run: auto-resume 1/2'"
check "new builder alive" kill -0 "$(reg t-run .builder_pid)"
tick
check "RUNNING after relaunch notified" [ "$(grep -c 't-run: RUNNING - ' "$WALKAWAY_HOME/logs/ntfy.log")" -eq 2 ]
kill_builder t-run; tick; tick
kill_builder t-run; tick
check "third death escalates (cap 2), no relaunch" [ "$(reg t-run .state)/$(reg t-run .launch_count)" == "ESCALATED/3" ]
check "ESCALATED ntfy is priority high" grep -q $'\thigh\tt-run: ESCALATED - ' "$WALKAWAY_HOME/logs/ntfy.log"
tick
check "ESCALATED is sticky (no new ntfy)" [ "$(grep -c 't-run: ESCALATED' "$WALKAWAY_HOME/logs/ntfy.log")" -eq 1 ]

# ── T3: scoped failure -> approve + relaunch ─────────────────────────────────
echo "T3 triage approve"
R2=$(drill_make_repo "$W/repos" r2 t-fail)
drill_set_modes "$R2" t-fail fail-scoped work
drill_failure "$R2" t-fail scoped
echo '{"decision":"approve","protected_hit":false,"in_scope":true,"directive":"Fix lib/export.sh total with awk.\nAdd regression test total=417.50; re-run phase 3 gates.\nThen continue from the build log.","rationale":"scoped"}' > "$W/decisions/t-fail.json"
launch "$R2" t-fail
sleep 6; tick; wait_operator t-fail
check "approved: relaunched with directive" [ "$(reg t-fail .launch_count)/$(reg t-fail .approvals)" == "2/1" ]
check "approving multi-line directive in plan" bash -c "grep -q '^Fix lib/export.sh total with awk.\$' '$R2/handoff/build-plan-t-fail.md' && grep -q '^Then continue from the build log.\$' '$R2/handoff/build-plan-t-fail.md'"
check "no stray plan tmp files" bash -c "! ls '$R2'/handoff/*.tmp.* >/dev/null 2>&1"
check "STOPPED notified once" [ "$(grep -c 't-fail: STOPPED - ' "$WALKAWAY_HOME/logs/ntfy.log")" -eq 1 ]
tick
check "back to RUNNING (failure report older than relaunch)" [ "$(reg t-fail .state)" == "RUNNING" ]
check "RUNNING ntfy names the operator action" grep -q 't-fail: RUNNING - approved fix 1, relaunched (builder pid [0-9]*); builder pid' "$WALKAWAY_HOME/logs/ntfy.log"

# ── T4: protected -> ESCALATE even if the model says approve ─────────────────
echo "T4 triage protected guard"
R3=$(drill_make_repo "$W/repos" r3 t-prot)
drill_set_modes "$R3" t-prot fail-protected
drill_failure "$R3" t-prot protected
echo '{"decision":"approve","protected_hit":true,"in_scope":true,"directive":"publish it","question":"Allow a live publish to Best of Kitchen, yes/no?","rationale":"live list"}' > "$W/decisions/t-prot.json"
launch "$R3" t-prot
sleep 6; tick; wait_operator t-prot
check "protected escalated, not relaunched" [ "$(reg t-prot .state)/$(reg t-prot .launch_count)" == "ESCALATED/1" ]
check "escalation carries the one question" grep -q 't-prot: ESCALATED - Allow a live publish to Best of Kitchen, yes/no?' "$WALKAWAY_HOME/logs/ntfy.log"
check "no directive written" bash -c "! grep -q 'RESUME DIRECTIVE' '$R3/handoff/build-plan-t-prot.md'"

# ── T5: bad evidence -> merge-gate rejection directive ───────────────────────
echo "T5 gate FAIL"
R4=$(drill_make_repo "$W/repos" r4 t-bad)
drill_set_modes "$R4" t-bad complete-bad work
drill_evidence "$R4" bad
echo '{"verdict":"FAIL","criteria":[{"id":"AC1","met":false,"evidence":"row 7 amount 99.99 vs 52.25"}],"ci_green":true,"codex_closed":true,"findings":["rows.json row 7 amount 99.99, source 52.25"],"directive":"merge-gate rejection: fix row 7 amount; regenerate summary; re-shoot result.png"}' > "$W/decisions/t-bad.json"
launch "$R4" t-bad
sleep 7; tick; wait_operator t-bad
check "DONE notified" grep -q 't-bad: DONE - PR #[0-9]* checks green; merge gate started' "$WALKAWAY_HOME/logs/ntfy.log"
check "rejection 1/2 relaunched" [ "$(reg t-bad .gate_rejections)/$(reg t-bad .launch_count)" == "1/2" ]
check "rejection directive in plan" grep -q '^## RESUME DIRECTIVE (auto, merge-gate rejection 1/2' "$R4/handoff/build-plan-t-bad.md"

# ── T6: good evidence -> merged + next queued plan launched ──────────────────
echo "T6 gate PASS + queue"
R5=$(drill_make_repo "$W/repos" r5 t-good t-next)
drill_set_modes "$R5" t-good complete-good
drill_set_modes "$R5" t-next work
drill_evidence "$R5" good
echo "$R5/handoff/build-plan-t-next.md" > "$WALKAWAY_HOME/queue/r5.txt"
echo '{"verdict":"PASS","criteria":[{"id":"AC1","met":true,"evidence":"10/10"},{"id":"AC2","met":true,"evidence":"417.50"}],"ci_green":true,"codex_closed":true,"findings":[],"rows_spot_checked":10,"screenshots_opened":1,"json_files_parsed":2}' > "$W/decisions/t-good.json"
launch "$R5" t-good
sleep 7; tick; wait_operator t-good
check "t-good MERGED" [ "$(reg t-good .state)" == "MERGED" ]
check "MERGED ntfy names the launched next plan" grep -q 't-good: MERGED - PR #[0-9]* squash-merged by merge gate; launched next: t-next' "$WALKAWAY_HOME/logs/ntfy.log"
check "origin main has the squash commit" bash -c "git -C '$W/repos/r5-origin.git' log main --format=%s | grep -q 'feature/t-good'"
check "local main fast-forwarded to merged origin main" bash -c "[[ \$(git -C '$R5' rev-parse main) == \$(git -C '$W/repos/r5-origin.git' rev-parse main) ]]"
check "queue popped" bash -c "! grep -q t-next '$WALKAWAY_HOME/queue/r5.txt'"
check "t-next registered + alive" kill -0 "$(reg t-next .builder_pid)"
tick
check "t-next RUNNING" [ "$(reg t-next .state)" == "RUNNING" ]
check "t-good stays MERGED, single MERGED ntfy" [ "$(grep -c 't-good: MERGED' "$WALKAWAY_HOME/logs/ntfy.log")" -eq 1 ]

# ── T7: walkaway status renders from the registry ────────────────────────────
echo "T7 status"
out=$(bash "$ROOT/walkaway.sh" status)
missing=0
for f in t-run t-fail t-prot t-bad t-good t-next; do grep -q "^$f " <<< "$out" || missing=1; done
check "status lists every build" [ "$missing" -eq 0 ]

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
