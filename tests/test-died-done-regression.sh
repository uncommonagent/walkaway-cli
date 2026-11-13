#!/usr/bin/env bash
# AC1 regression: replay the 11/13 bf-deals-ingest-fix timeline through real supervisor ticks.
#
# What happened (handoff/operator-log-bf-deals-ingest-fix.md in audrey-ops-platform):
#   09:28:06  builder committed build-report-bf-deals-ingest-fix.md (PR #28 open, Vercel still pending), exited
#   09:28:47  tick: report newer than launch, but CI not green -> fell through to liveness -> DIED -> resume 1/2
#   09:30:49  the resumed builder found nothing to do, exited -> DIED (report now older than the relaunch) -> 2/2
#   09:32:51  cap -> ESCALATED "Relaunch it, or stop this build?" for a finished build (PR #28 green)
# Expected now: DONE at the first tick after the report (zero resumes, no DIED ntfy), the merge gate starts
# once CI is green.
#
# WALKAWAY_LIB=<dir> runs the replay against another lib/ (e.g. the pre-fix commit) to prove the test fails there.
# Exit 0 = all pass.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${WALKAWAY_LIB:-${SCRIPT_DIR}/../lib}"
W=$(mktemp -d)
export WALKAWAY_HOME="$W/home" WALKAWAY_NTFY_DISABLED=1 NTFY_TOPIC=regression WALKAWAY_CLAUDE_PROJECTS="$W/none"
export WALKAWAY_GH_CMD="$W/gh" WALKAWAY_OPERATOR_CMD="$W/claude" WALKAWAY_SH="$W/walkaway-stub.sh"
export WALKAWAY_LAUNCH_LOG_DIR="$W/logs" PR_JSON="$W/pr.json"
mkdir -p "$WALKAWAY_HOME/registry" "$W/logs"

PASS=0
FAIL=0
check() { local label="$1"; shift; if "$@"; then echo "  PASS: $label"; PASS=$((PASS + 1)); else echo "  FAIL: $label"; FAIL=$((FAIL + 1)); fi; }
reg() { jq -r "$1 // empty" "$WALKAWAY_HOME/registry/bf-deals-ingest-fix.json"; }
tick() { bash "$LIB/supervisor.sh" tick >> "$W/supervisor.log" 2>&1; }
ntfy() { grep -c "bf-deals-ingest-fix: $1 - " "$WALKAWAY_HOME/logs/ntfy.log" 2>/dev/null || true; }
pr() { # state rollup-conclusion
  printf '{"number":28,"state":"%s","headRefOid":"x","statusCheckRollup":[{"__typename":"CheckRun","name":"Vercel","status":"%s","conclusion":"%s"}]}\n' \
    "$1" "$( [[ "$2" == pending ]] && echo IN_PROGRESS || echo COMPLETED)" "$( [[ "$2" == pending ]] && echo "" || echo SUCCESS)" > "$PR_JSON"
}
at() { date -v"$1"S '+%Y-%m-%dT%H:%M:%S'; } # seconds relative to now -> git date

cat > "$W/gh" <<'EOF'
#!/usr/bin/env bash
cat "$PR_JSON"
EOF
# Merge-gate stand-in: proves the gate was reached, then escalates (no merge machinery in this replay).
cat > "$W/claude" <<'EOF'
#!/usr/bin/env bash
echo '{"structured_output":{"verdict":"ESCALATE","criteria":[],"ci_green":true,"codex_closed":true,"findings":[],"question":"regression replay: merge gate reached"}}'
EOF
# A relaunch must never happen; if the old code tries one, record it and fail fast.
cat > "$W/walkaway-stub.sh" <<EOF
#!/usr/bin/env bash
echo "relaunch \$*" >> "$W/relaunches.log"
exit 1
EOF
chmod +x "$W/gh" "$W/claude" "$W/walkaway-stub.sh"

builder_pid=""
cleanup() { [[ -n "$builder_pid" ]] && kill "$builder_pid" 2>/dev/null; [[ -n "${KEEP_WORK:-}" ]] && echo "kept $W" || rm -rf "$W"; }
trap cleanup EXIT

# The build repo on feature/bf-deals-ingest-fix, launched 25 min before the report (09:03 in the real timeline).
R="$W/audrey-ops-platform"
mkdir -p "$R/handoff"
git -C "$R" init -q -b feature/bf-deals-ingest-fix
git -C "$R" config user.name replay; git -C "$R" config user.email replay@example.invalid
printf '# Walkaway Build Plan: bf-deals-ingest-fix\n\n## Feature name\n`bf-deals-ingest-fix`\n\n## Branch name\n`feature/bf-deals-ingest-fix`\n' > "$R/handoff/build-plan-bf-deals-ingest-fix.md"
git -C "$R" add -A
GIT_AUTHOR_DATE=$(at -1500) GIT_COMMITTER_DATE=$(at -1500) git -C "$R" commit -qm "build plan"

sleep 600 > /dev/null 2>&1 &
builder_pid=$!
bash -c "source '$LIB/registry.sh'; registry_register bf-deals-ingest-fix '$R' '$R' '$R/handoff/build-plan-bf-deals-ingest-fix.md' feature/bf-deals-ingest-fix $builder_pid '' '' false"
jq --argjson t "$(date -v-1500S +%s)" '.launched_epoch = $t | .state_since = $t' "$WALKAWAY_HOME/registry/bf-deals-ingest-fix.json" > "$W/r" && mv "$W/r" "$WALKAWAY_HOME/registry/bf-deals-ingest-fix.json"
echo "replaying 11/13 bf-deals-ingest-fix against $LIB"

# 09:2x: builder mid-phase, no PR yet.
echo '{}' > "$PR_JSON"
tick
check "builder working -> RUNNING" [ "$(reg .state)" == "RUNNING" ]

# 09:28:06: Phase 8 - PR #28 opened, build report committed LAST, builder exits. Vercel still building.
pr OPEN pending
echo "- Phase 8: PR #28 opened, build report next" >> "$R/handoff/build-log-bf-deals-ingest-fix.md"
printf '# Build report - bf-deals-ingest-fix\n\nCOMPLETE. PR #28.\n' > "$R/handoff/build-report-bf-deals-ingest-fix.md"
git -C "$R" add -A
GIT_AUTHOR_DATE=$(at -41) GIT_COMMITTER_DATE=$(at -41) git -C "$R" commit -qm "build report: bf-deals-ingest-fix"
touch -t "$(date -v-41S +%Y%m%d%H%M.%S)" "$R"/handoff/*
kill "$builder_pid"; wait "$builder_pid" 2>/dev/null; builder_pid=""

# 09:28:47: the tick that fired DIED on 11/13.
tick
check "09:28:47 tick: DONE, not DIED" [ "$(reg .state)" == "DONE" ]
check "DONE records pending CI and waits" bash -c "[[ '$(reg .last_action)' == 'PR #28 checks pending; merge gate waits for green CI' ]]"
check "no DIED ntfy" [ "$(ntfy DIED)" -eq 0 ]
check "zero resumes (resume_count 0, launch_count 1)" [ "$(reg .resume_count)/$(reg .launch_count)" == "0/1" ]
check "no RESUME DIRECTIVE written to the plan" bash -c "! grep -q 'RESUME DIRECTIVE' '$R/handoff/build-plan-bf-deals-ingest-fix.md'"
check "no relaunch attempted" test ! -e "$W/relaunches.log"

# 09:30:49 and 09:32:51: the ticks that resumed again and escalated on 11/13. CI still pending.
tick; tick
check "later ticks: still DONE, still zero resumes" [ "$(reg .state)/$(reg .resume_count)/$(reg .launch_count)" == "DONE/0/1" ]
check "exactly one DONE ntfy, no ESCALATED" [ "$(ntfy DONE)/$(ntfy ESCALATED)" == "1/0" ]

# Vercel turns green: the merge gate starts (one gate per launch).
pr OPEN green
tick
check "green CI starts the merge gate" [ "$(reg .operator_mode)/$(reg .operator_launch)" == "gate/1" ]
for _ in $(seq 1 30); do p=$(reg .operator_pid); { [[ -z "$p" ]] || ! kill -0 "$p" 2>/dev/null; } && break; sleep 1; done
check "gate reached (stand-in verdict logged)" grep -q 'regression replay: merge gate reached' "$R/handoff/operator-log-bf-deals-ingest-fix.md"
check "whole replay: zero resumes, zero DIED" [ "$(reg .resume_count)/$(ntfy DIED)" == "0/0" ]
echo "  ntfy lines:"; sed 's/^/    /' "$WALKAWAY_HOME/logs/ntfy.log"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
