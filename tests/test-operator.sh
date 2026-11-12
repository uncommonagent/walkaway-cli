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
export WALKAWAY_MERGE_CHECK_WAIT=30 WALKAWAY_MERGE_CHECK_POLL=1 NTFY_TOPIC=test-topic
mkdir -p "$WALKAWAY_HOME/queue" "$WALKAWAY_LAUNCH_LOG_DIR" "$W/decisions"
touch "$WALKAWAY_HOME/supervisor.enabled"

# claude stub: returns $W/decisions/<feature>.json as structured_output; runs $W/decisions/<feature>.hook
# first if present (lets a test change the world mid-gate, e.g. make gh fail after the verdict).
cat > "$W/stub-claude" <<EOF
#!/usr/bin/env bash
feature=\$(printf '%s\n' "\$2" | sed -n 's/^Feature: //p' | head -1)
echo "\$(date +%T) stub-claude \$feature" >> "$W/stub-claude.log"
[[ -f "$W/decisions/\$feature.hook" ]] && bash "$W/decisions/\$feature.hook"
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
  # A relaunch re-registers (operator_pid -> null, last_action "relaunched") before the operator records its
  # action, so also wait for that interim last_action to be replaced.
  local p
  for _ in $(seq 1 60); do
    p=$(reg "$1" .operator_pid)
    { [[ -z "$p" ]] || ! kill -0 "$p" 2>/dev/null; } && [[ "$(reg "$1" .last_action)" != "relaunched" ]] && return 0
    sleep 1
  done
}
launch() { # repo feature
  (cd "$1" || exit 1; nohup bash "$ROOT/walkaway.sh" "$1/handoff/build-plan-$2.md" > "$W/logs/walkaway-$2.log" 2>&1 < /dev/null &)
  local _
  for _ in $(seq 1 30); do [[ -f "$WALKAWAY_HOME/registry/$2.json" ]] && return 0; sleep 1; done
}
kill_builder() { kill "$(reg "$1" .builder_pid)"; sleep 1; }
PASS_DECISION='{"verdict":"PASS","criteria":[{"id":"AC1","met":true,"evidence":"10/10"}],"ci_green":true,"codex_closed":true,"findings":[],"rows_spot_checked":10}'
# wt_build <repo-name> <feature>: a DONE worktree build (branch checked out in <repo>-<feature>, PR open +
# green, untracked builder artifact in the worktree), registered like `walkaway --worktree` does. A real
# --worktree launch would run npm install and open VS Code, so the worktree is made directly. Echoes the root.
wt_build() {
  local root wt bpid
  root=$(drill_make_repo "$W/repos" "$1" "$2")
  wt="$W/repos/$1-$2"
  git -C "$root" worktree add -q "$wt" -b "feature/$2"
  (
    cd "$wt" || exit 1
    printf '# Build report - %s\n' "$2" > "handoff/build-report-$2.md"
    git add handoff && git commit -qm "$2 build report" && git push -q -u origin "feature/$2"
    "$WALKAWAY_GH_CMD" pr create-sim "feature/$2" > /dev/null
  )
  echo "builder scratch, never committed" > "$wt/handoff/untracked-artifact.txt"
  sleep 600 > /dev/null 2>&1 &
  bpid=$!
  bash -c "source '$ROOT/lib/registry.sh'; registry_register '$2' '$wt' '$root' '$wt/handoff/build-plan-$2.md' 'feature/$2' '$bpid' '' '' true"
  echo "$root"
}
gate() { bash "$ROOT/lib/operator.sh" gate "$1" >> "$W/operator-$1.log" 2>&1; }
merge_calls() { grep "/$1 gh pr merge" "$GH_SIM_DIR/calls.log" 2>/dev/null; }

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
check "no uncommitted operator-log change in the repo after the merge" \
  bash -c "[[ -z \$(git -C '$R5' status --porcelain -- handoff/operator-log-t-good.md) ]]"
check "MERGED outcome in \$WALKAWAY_HOME operator log" grep -q 'MERGED: PR #[0-9]* squash-merged by merge gate. launched next: t-next' "$WALKAWAY_HOME/logs/operator-t-good.log"

# ── T8: PASS with codex_closed:false -> FAIL/rejection, never merged ─────────
echo "T8 gate PASS without Codex closure"
R6=$(drill_make_repo "$W/repos" r6 t-codex)
drill_set_modes "$R6" t-codex complete-good work
drill_evidence "$R6" good
jq -c '.codex_closed = false' <<< "$PASS_DECISION" > "$W/decisions/t-codex.json"
launch "$R6" t-codex
sleep 7; tick; wait_operator t-codex
check "downgraded to rejection 1/2 + relaunched" [ "$(reg t-codex .gate_rejections)/$(reg t-codex .launch_count)" == "1/2" ]
check "rejection directive in plan" grep -q '^## RESUME DIRECTIVE (auto, merge-gate rejection 1/2' "$R6/handoff/build-plan-t-codex.md"
check "gh pr merge NOT called" bash -c "! grep -q '/r6 gh pr merge' '$GH_SIM_DIR/calls.log'"

# ── T9: gh pr view failing during the post-gate CI wait -> escalate, no merge ─
echo "T9 CI wait fails closed"
wt_build r7 t-ghdown > /dev/null
echo "$PASS_DECISION" > "$W/decisions/t-ghdown.json"
echo "touch '$GH_SIM_DIR/fail-view'" > "$W/decisions/t-ghdown.hook"
gate t-ghdown
rm -f "$GH_SIM_DIR/fail-view"
check "escalated (checks not verified)" grep -q 't-ghdown: ESCALATED - Merge gate passed for t-ghdown but PR #[0-9]* checks are not green' "$WALKAWAY_HOME/logs/ntfy.log"
check "gh pr merge NOT called" bash -c "[[ -z \$(grep '/r7 gh pr merge' '$GH_SIM_DIR/calls.log') ]]"

# ── T10: worktree build, gh pr merge fails -> nothing removed, escalation in the worktree ─
echo "T10 worktree merge failure"
R8=$(wt_build r8 t-wtfail)
WT8="$W/repos/r8-t-wtfail"
echo "$PASS_DECISION" > "$W/decisions/t-wtfail.json"
touch "$GH_SIM_DIR/fail-merge"
gate t-wtfail
rm -f "$GH_SIM_DIR/fail-merge"
check "merge was attempted" bash -c "[[ -n \$(grep '/r8 gh pr merge' '$GH_SIM_DIR/calls.log') ]]"
check "worktree still a valid git worktree" git -C "$WT8" rev-parse --git-dir
check "untracked builder artifact survived" test -f "$WT8/handoff/untracked-artifact.txt"
check "local + remote branch not deleted" bash -c "git -C '$R8' show-ref -q --verify refs/heads/feature/t-wtfail && [[ -n \$(git -C '$R8' ls-remote --heads origin feature/t-wtfail) ]]"
check "escalated with the merge error" grep -q 't-wtfail: ESCALATED - gh pr merge failed for t-wtfail PR #[0-9]*: gh-sim: simulated merge conflict' "$WALKAWAY_HOME/logs/ntfy.log"
check "escalation logged + committed inside the worktree" bash -c "grep -q '^## .* - ESCALATED' '$WT8/handoff/operator-log-t-wtfail.md' && git -C '$WT8' log -1 --format=%s | grep -q 'operator: t-wtfail: escalated'"

# ── T11: worktree build, merge succeeds -> no --delete-branch, prune + branch delete after ─
echo "T11 worktree merge success"
R9=$(wt_build r9 t-wtok)
WT9="$W/repos/r9-t-wtok"
echo "$PASS_DECISION" > "$W/decisions/t-wtok.json"
gate t-wtok
check "t-wtok MERGED" [ "$(reg t-wtok .state)" == "MERGED" ]
check "merge called without --delete-branch" bash -c "merge=\$(grep '/r9 gh pr merge' '$GH_SIM_DIR/calls.log') && [[ -n \$merge && \$merge != *--delete-branch* ]]"
check "worktree still present at merge time (pruned after)" bash -c "grep -A1 '/r9 gh pr merge' '$GH_SIM_DIR/calls.log' | grep -q 'worktrees at merge: 2'"
check "worktree pruned after the merge" bash -c "[[ ! -e '$WT9' ]] && ! git -C '$R9' worktree list | grep -q r9-t-wtok"
check "remote + local branch deleted" bash -c "[[ -z \$(git -C '$R9' ls-remote --heads origin feature/t-wtok) ]] && ! git -C '$R9' show-ref -q --verify refs/heads/feature/t-wtok"
check "origin main has the squash commit" bash -c "git -C '$W/repos/r9-origin.git' log main --format=%s | grep -q 'feature/t-wtok'"
check "repo checkout clean after the merge" bash -c "[[ -z \$(git -C '$R9' status --porcelain) ]]"

# ── T12: GitHub still reports the pre-push head (old green rollup) -> no merge until the head matches ─
echo "T12 stale head after the gate push"
wt_build r10 t-stale > /dev/null
echo "$PASS_DECISION" > "$W/decisions/t-stale.json"
cat > "$W/decisions/t-stale.hook" <<EOF
touch '$GH_SIM_DIR/stale-head'
( for i in \$(seq 1 300); do grep -q '  view: stale head' '$GH_SIM_DIR/calls.log' && break; sleep 0.2; done
  sleep 2; rm -f '$GH_SIM_DIR/stale-head'; echo "  stale-head cleared \$(date +%s)" >> '$GH_SIM_DIR/calls.log' ) > /dev/null 2>&1 &
EOF
gate t-stale
check "stale head was observed" grep -q '  view: stale head' "$GH_SIM_DIR/calls.log"
check "t-stale MERGED once the head matched" [ "$(reg t-stale .state)" == "MERGED" ]
check "gh pr merge called only after the head matched" \
  awk '/stale-head cleared/ { c = NR } /\/r10 gh pr merge/ { m = NR } END { exit !(c && m && m > c) }' "$GH_SIM_DIR/calls.log"

echo "T12b head never matches -> escalate, no merge"
wt_build r11 t-stuck > /dev/null
echo "$PASS_DECISION" > "$W/decisions/t-stuck.json"
echo "touch '$GH_SIM_DIR/stale-head'" > "$W/decisions/t-stuck.hook"
WALKAWAY_MERGE_CHECK_WAIT=4 gate t-stuck
rm -f "$GH_SIM_DIR/stale-head"
check "escalated: head never reached the gate commit" grep -q 't-stuck: ESCALATED - Merge gate passed for t-stuck but PR #[0-9]* checks are not green after the gate push (PR head never reached the gate commit' "$WALKAWAY_HOME/logs/ntfy.log"
check "gh pr merge NOT called" bash -c "[[ -z \$(grep '/r11 gh pr merge' '$GH_SIM_DIR/calls.log') ]]"

# ── T13: empty rollup on the matching head -> merge only after the grace window ─
echo "T13 empty rollup grace"
wt_build r12 t-empty > /dev/null
echo "$PASS_DECISION" > "$W/decisions/t-empty.json"
echo "touch '$GH_SIM_DIR/empty-checks'" > "$W/decisions/t-empty.hook"
WALKAWAY_MERGE_EMPTY_CHECKS_GRACE=2 gate t-empty
rm -f "$GH_SIM_DIR/empty-checks"
check "t-empty MERGED after the grace window" [ "$(reg t-empty .state)" == "MERGED" ]
check "merge >= 2s after the first empty-rollup view" \
  awk '/  view: empty rollup / && !f { f = $4 } /\/r12 gh pr merge/ { m = $2 } END { exit !(f && m && m - f >= 2) }' "$GH_SIM_DIR/calls.log"

# ── T14: worktree merge while another build runs in the root checkout -> root untouched, queue held ─
echo "T14 post-merge sync with an active root builder"
R13=$(wt_build r13 t-wtroot)
git -C "$R13" checkout -q -b feature/t-rootbusy
sleep 600 > /dev/null 2>&1 &
bash -c "source '$ROOT/lib/registry.sh'; registry_register t-rootbusy '$R13' '$R13' '$R13/handoff/build-plan-t-rootbusy.md' feature/t-rootbusy '$!' '' '' false"
mkdir -p "$W/plans"; drill_plan t-q13 > "$W/plans/build-plan-t-q13.md"
echo "$W/plans/build-plan-t-q13.md" > "$WALKAWAY_HOME/queue/r13.txt"
head13=$(git -C "$R13" rev-parse HEAD); reflog13=$(git -C "$R13" reflog | wc -l)
echo "$PASS_DECISION" > "$W/decisions/t-wtroot.json"
gate t-wtroot
check "t-wtroot MERGED" [ "$(reg t-wtroot .state)" == "MERGED" ]
check "root still on the active build's branch at the same HEAD" \
  bash -c "[[ \$(git -C '$R13' symbolic-ref --short HEAD) == feature/t-rootbusy && \$(git -C '$R13' rev-parse HEAD) == '$head13' ]]"
check "no checkout or pull ran in the root (HEAD reflog unchanged)" [ "$(git -C "$R13" reflog | wc -l)" -eq "$reflog13" ]
check "remote refs fetched (origin/main has the squash commit)" bash -c "git -C '$R13' log origin/main --format=%s | grep -q 'feature/t-wtroot'"
check "sync deferral logged" grep -q 'default-branch sync deferred: t-rootbusy active in root' "$WALKAWAY_HOME/logs/operator-t-wtroot.log"
check "queue held" bash -c "grep -q t-q13 '$WALKAWAY_HOME/queue/r13.txt' && grep -q 't-wtroot: MERGED - .*held: t-rootbusy still active' '$WALKAWAY_HOME/logs/ntfy.log'"

# ── T15: the gate push is rejected -> escalate, gh pr merge never called ─────
echo "T15 gate push failure"
wt_build r14 t-pushfail > /dev/null
printf '#!/bin/sh\necho "rejected by test pre-receive hook" >&2\nexit 1\n' > "$W/repos/r14-origin.git/hooks/pre-receive"
chmod +x "$W/repos/r14-origin.git/hooks/pre-receive"
echo "$PASS_DECISION" > "$W/decisions/t-pushfail.json"
gate t-pushfail
check "escalated: PASS could not be pushed" grep -q 't-pushfail: ESCALATED - Merge gate PASS for t-pushfail could not be pushed (.*). Push/merge manually?' "$WALKAWAY_HOME/logs/ntfy.log"
check "gh pr merge NOT called" bash -c "[[ -z \$(grep '/r14 gh pr merge' '$GH_SIM_DIR/calls.log') ]]"

# ── T7: walkaway status renders from the registry ────────────────────────────
echo "T7 status"
out=$(bash "$ROOT/walkaway.sh" status)
missing=0
for f in t-run t-fail t-prot t-bad t-good t-next t-codex t-ghdown t-wtfail t-wtok t-stale t-stuck t-empty t-wtroot t-rootbusy t-pushfail; do
  grep -q "^$f " <<< "$out" || missing=1
done
check "status lists every build" [ "$missing" -eq 0 ]

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
