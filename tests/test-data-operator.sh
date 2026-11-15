#!/usr/bin/env bash
# Data operator (lib/data-operator.sh) + its hand-off from the data watch (lib/data.sh) in a scratch world: scratch
# series (tests/fixtures/data/series-test.yaml) with owner repo = a scratch repo, fixture counts, stubbed re-pull
# triggers, walkaway launches with the stub builder, claude -p replaced by a stub returning canned decisions, ntfy
# recorded to ntfy.log only. Exit 0 = all pass.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/.."
# shellcheck source=tests/drill/scratch.sh
source "${SCRIPT_DIR}/drill/scratch.sh"

W=$(mktemp -d)
export WALKAWAY_HOME="$W/home" WALKAWAY_NTFY_DISABLED=1 NTFY_TOPIC=data-op-test WALKAWAY_HEARTBEAT_HOURS=off
export WALKAWAY_BUILDER_CMD="${SCRIPT_DIR}/drill/stub-builder.sh" WALKAWAY_GH_CMD="${SCRIPT_DIR}/drill/gh-sim.sh" GH_SIM_DIR="$W/gh"
export WALKAWAY_OPERATOR_CMD="$W/stub-claude" WALKAWAY_LAUNCH_LOG_DIR="$W/logs" WALKAWAY_CLAUDE_PROJECTS="$W/none"
export WALKAWAY_DATA_FILE="$W/series.yaml" WALKAWAY_DATA_FIXTURES="$W/fx" WALKAWAY_DATA_TRIGGER_CMD="$ROOT/tests/fixtures/data/trigger-stub.sh"
export WALKAWAY_DATA_GUARD_FIXTURE="$W/guard.json"
mkdir -p "$WALKAWAY_HOME/queue" "$W/logs" "$W/decisions" "$W/fx"
echo '[]' > "$W/guard.json"
touch "$WALKAWAY_HOME/supervisor.enabled"

PASS=0
FAIL=0
check() { local label="$1"; shift; if "$@"; then echo "  PASS: $label"; PASS=$((PASS + 1)); else echo "  FAIL: $label"; FAIL=$((FAIL + 1)); fi; }
at() { export WALKAWAY_DATA_NOW; WALKAWAY_DATA_NOW=$(TZ=America/New_York date -j -f '%Y-%m-%d %H:%M' "$1" +%s); }
fill() {
  python3 - "$W/fx/$1.json" "$2" "$3" "$4" <<'PY'
import json, sys, datetime, os
p, a, b, c = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
d = json.load(open(p)) if os.path.exists(p) else {}
x = datetime.date.fromisoformat(a); e = datetime.date.fromisoformat(b)
while x <= e:
    d[x.isoformat()] = c; x += datetime.timedelta(days=1)
json.dump(d, open(p, "w"))
PY
}
gst() { jq -r --arg p "$2" ".gaps[\$p].$3 // empty" "$WALKAWAY_HOME/data/state/$1.json" 2>/dev/null; }
sget() { jq -r ".$2 // empty" "$WALKAWAY_HOME/data/state/$1.json" 2>/dev/null; }
nt() { local n; n=$(grep -c "data $1: $2 - " "$WALKAWAY_HOME/logs/ntfy.log" 2>/dev/null); echo "${n:-0}"; }
trig() { local n; n=$(grep -c "^$1 " "$WALKAWAY_HOME/triggers.log" 2>/dev/null); echo "${n:-0}"; }
# ev <series>: one data-watch tick for the series, then wait for a spawned data operator to finish (max 60 s).
ev() {
  bash "$ROOT/lib/data.sh" evaluate "$1" >> "$W/data.log" 2>&1
  local p i
  p=$(sget "$1" operator_pid)
  for (( i = 0; i < 60; i++ )); do [[ -n "$p" ]] && kill -0 "$p" 2>/dev/null || break; sleep 1; done
}

cleanup() {
  local f p
  for f in "$W"/home/registry/*.json; do
    [[ -f "$f" ]] || continue
    for p in $(jq -r '.builder_pid, .watcher_pid | select(. != null)' "$f"); do pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null; done
  done
  [[ -n "${KEEP_WORK:-}" ]] && echo "kept $W" || rm -rf "$W"
}
trap cleanup EXIT

# claude stub: the decision for the series named on the task's "Series: <name> (" line.
cat > "$W/stub-claude" <<EOF
#!/usr/bin/env bash
s=\$(printf '%s\n' "\$2" | sed -n 's/^Series: \([a-z0-9-]*\) (.*/\1/p' | head -1)
echo "\$(date +%T) stub-claude \$s cwd=\$(pwd)" >> "$W/stub-claude.log"
jq -c '{structured_output: .}' "$W/decisions/\$s.json"
EOF
chmod +x "$W/stub-claude"

# Scratch owner repo; the test series with their owner repo pointed at it (JSON is valid YAML).
R1=$(drill_make_repo "$W/repos" audrey-scratch)
drill_set_modes "$R1" fix-data-scratch-amazon-20261118 work
WALKAWAY_DATA_FILE="$ROOT/tests/fixtures/data/series-test.yaml" bash -c "source '$ROOT/lib/data.sh'; data_config" |
  jq --arg r "$R1" '.series |= map(.owner_repo = $r)' > "$W/series.yaml"

FIX_DECISION='{"decision":"fix","protected_hit":false,"needs_live_action":false,"confidence":"high",
 "cause":"No re-pull path covers ages 9-10: run-now pulls yesterday only and the self-heal window ends at today-8 (missing/route.ts eligibleDates). The 11-08/11-09 pulls failed on a logged-in session that later recovered.",
 "evidence":["counts 2026-11-08=0, 2026-11-09=0 (floor 5)","src/app/api/ingest/amazon/missing/route.ts:41-48 eligibleDates"],
 "fix":{"title":"Date-range re-pull hook for tracking","goal":"The supervisor can re-pull any tracking date range through the existing heal path.",
   "what_to_build":["extension/background.js: URL trigger #sr-ext-repull=tracking_offsite&from=..&to=.. -> runReport(customDate) per date"],
   "acceptance_criteria":[{"id":"AC1","text":"hook pulls exactly 2026-11-08..2026-11-09 in a fixture run","evidence_file":"handoff/fix-data-scratch-amazon-20261118-evidence/hook-test.txt"}],
   "regression_fixture":"counts 11-08=0 / 11-09=0 with no covering method",
   "files_expected":["extension/background.js","extension/heal-lib.js","tests/heal-hook.test.ts"],
   "do_not_build":["No change to the scheduled morning pull"],"stop_rules":["Stop if the hook needs a credential"]}}'

echo "O1 lost data: the source cannot re-pull a past day -> ESCALATED (high) naming the lost dates, no model"
at "2026-11-18 14:00"
fill scratch-lost 2026-11-01 2026-11-18 4; fill scratch-lost 2026-11-15 2026-11-16 0
ev scratch-lost
check "gaps ESCALATED + marked lost" bash -c "[[ \$(jq -r '.gaps[\"2026-11-15\"].state' '$WALKAWAY_HOME/data/state/scratch-lost.json') == ESCALATED && \$(jq -r '.gaps[\"2026-11-16\"].lost' '$WALKAWAY_HOME/data/state/scratch-lost.json') == true ]]"
check "one ESCALATED ntfy, priority high, with the dates and the reason" grep -q $'\thigh\tdata scratch-lost: ESCALATED - scratch-lost lost 2026-11-15, 2026-11-16 (0/4 rows): the source cannot re-pull a past day. Accept the loss, or fix the pull so it stops missing days?$' "$WALKAWAY_HOME/logs/ntfy.log"
check "claude not asked (deterministic)" bash -c "! grep -q 'stub-claude scratch-lost' '$W/stub-claude.log' 2>/dev/null"
check "incident file written" test -f "$WALKAWAY_HOME/data-fixes/scratch-lost-2026-11-18/handoff/job-incident-scratch-lost-2026-11-18.md"
ev scratch-lost
check "next tick: nothing new (no re-escalation, no operator)" [ "$(nt scratch-lost ESCALATED)" -eq 1 ]

echo "O2 no re-pull path (historical yes) -> diagnosis -> template-v2 fix plan with the hook contract, launched (FIXING)"
at "2026-11-18 13:00"
fill scratch-amazon 2026-11-01 2026-11-17 9; fill scratch-amazon 2026-11-08 2026-11-09 0
echo "$FIX_DECISION" > "$W/decisions/scratch-amazon.json"
ev scratch-amazon
WS="$WALKAWAY_HOME/data-fixes/scratch-amazon-2026-11-18/handoff"
PLAN="$WS/build-plan-fix-data-scratch-amazon-20261118.md"
INC="$WS/job-incident-scratch-amazon-2026-11-18.md"
check "claude ran read-only in the owner repo" grep -q "stub-claude scratch-amazon cwd=$R1\$" "$W/stub-claude.log"
check "incident: gaps with counts + reason, cause, fresh counts" bash -c "grep -q '2026-11-08: missing - rows 0 / floor 5' '$INC' && grep -q 'no re-pull path for age 10' '$INC' && grep -q '^## Cause' '$INC' && grep -q 'Fresh read-only counts' '$INC'"
check "plan has every template-v2 section" bash -c "for s in '## Feature name' '## Branch name' '## Repo' '## Goal' '## Non-goals' '## Evidence' '## Decisions' '## Quality rules' '## Source of truth' '## Acceptance criteria' '## Gate checklist' '## Escalate to Jim' '## Expected files touched' '## Phases' '## Do NOT build' '## Stop rules'; do grep -q \"^\$s\" '$PLAN' || exit 1; done"
check "plan states the hook contract verbatim + the supervisor's exact call" bash -c "grep -qF 'test hook #sr-ext-repull=tracking_offsite&from=..&to=..' '$PLAN' && grep -qF 'Supervisor call: \`echo fix-hook {from} {to}\`' '$PLAN' && grep -q '^- \[ \] ACH ' '$PLAN'"
check "plan parses: feature, branch, repo = owner repo" bash -c "[[ \$(bash '$ROOT/lib/parse-plan.sh' '$PLAN' | tr '\n' ' ') == 'FEATURE_NAME=fix-data-scratch-amazon-20261118 BRANCH_NAME=feature/fix-data-scratch-amazon-20261118 REPO_PATH=$R1 ' ]]"
check "fix build launched and registered in the owner repo" bash -c "[[ \$(jq -r .repo '$WALKAWAY_HOME/registry/fix-data-scratch-amazon-20261118.json') == '$R1' ]]"
check "gaps FIXING; exactly one OPEN and one FIXING ntfy" bash -c "[[ \$(jq -r '.gaps[\"2026-11-09\"].state' '$WALKAWAY_HOME/data/state/scratch-amazon.json') == FIXING ]] && [[ \$(grep -c 'data scratch-amazon: OPEN - ' '$WALKAWAY_HOME/logs/ntfy.log') -eq 1 && \$(grep -c 'data scratch-amazon: FIXING - 2026-11-08, 2026-11-09: cause: No re-pull path covers ages 9-10.*fix build fix-data-scratch-amazon-20261118 launched' '$WALKAWAY_HOME/logs/ntfy.log') -eq 1 ]]"

echo "O3 fix in flight: ticks follow the build, no trigger, no second plan"
at "2026-11-18 13:10"; ev scratch-amazon
check "last action follows the fix build" bash -c "[[ \$(jq -r .last_action '$WALKAWAY_HOME/data/state/scratch-amazon.json') == 'fix build fix-data-scratch-amazon-20261118 '* ]]"
check "no trigger, claude asked once" bash -c "[[ \$(grep -c '^scratch-amazon ' '$WALKAWAY_HOME/triggers.log' 2>/dev/null || true) -eq 0 && \$(grep -c 'stub-claude scratch-amazon' '$W/stub-claude.log') -eq 1 ]]"

echo "O4 fix MERGED -> gaps back to OPEN, the hook re-pulls exactly the gap dates, rows land -> CLOSED (one ntfy each)"
bash -c "source '$ROOT/lib/registry.sh'; registry_update fix-data-scratch-amazon-20261118 '.state = \"MERGED\"'"
export STUB_LAND=9
at "2026-11-18 14:00"; ev scratch-amazon
unset STUB_LAND
check "hook fired once for 2026-11-08..2026-11-09" bash -c "[[ \$(grep -c '^scratch-amazon ' '$WALKAWAY_HOME/triggers.log') -eq 1 ]] && grep -q '^scratch-amazon command echo fix-hook {from} {to} 2026-11-08 2026-11-09$' '$WALKAWAY_HOME/triggers.log'"
check "fix recorded merged + hook enabled" bash -c "[[ \$(jq -r '.fix_merged, .hook_merged' '$WALKAWAY_HOME/data/state/scratch-amazon.json' | tr '\n' ' ') == 'true true ' ]]"
at "2026-11-18 14:02"; ev scratch-amazon
check "CLOSED rows 0 -> 9 via the fix hook" bash -c "[[ \$(jq -r '.gaps[\"2026-11-08\"].state' '$WALKAWAY_HOME/data/state/scratch-amazon.json') == CLOSED ]] && grep -q 'data scratch-amazon: CLOSED - 2026-11-08 rows 0 -> 9, 2026-11-09 rows 0 -> 9 (floor 5; via command (fix hook): echo fix-hook {from} {to})' '$WALKAWAY_HOME/logs/ntfy.log'"
check "exactly one ntfy per transition: OPEN 1, FIXING 1, CLOSED 1, ESCALATED 0" bash -c "[[ \$(grep -c 'data scratch-amazon: OPEN - ' '$WALKAWAY_HOME/logs/ntfy.log') == 1 && \$(grep -c 'data scratch-amazon: FIXING - ' '$WALKAWAY_HOME/logs/ntfy.log') == 1 && \$(grep -c 'data scratch-amazon: CLOSED - ' '$WALKAWAY_HOME/logs/ntfy.log') == 1 && \$(grep -c 'data scratch-amazon: ESCALATED - ' '$WALKAWAY_HOME/logs/ntfy.log') == 0 ]]"

echo "O5 post-fix re-pull fails twice -> ESCALATED (no second fix build, no model)"
cp "$W/stub-claude.log" "$W/stub-claude.log.before" 2>/dev/null || true
W3=$(mktemp -d); export WALKAWAY_HOME="$W3/home"; mkdir -p "$WALKAWAY_HOME/data/state" "$WALKAWAY_HOME/registry"
echo '{"feature":"fix-x","state":"MERGED","repo":"/nowhere"}' > "$WALKAWAY_HOME/registry/fix-x.json"
jq -n '{series: "scratch-amazon", ok_periods: [], fix_feature: "fix-x", fix_merged: false, fix_date: "2026-11-17",
        gaps: {"2026-11-07": {state: "FIXING", status: "missing", rows_before: 0, rows_now: 0, failed_tries: 2, tries_today: 0}}}' \
  > "$WALKAWAY_HOME/data/state/scratch-amazon.json"
fill scratch-amazon 2026-11-01 2026-11-18 9; fill scratch-amazon 2026-11-07 2026-11-07 0
at "2026-11-18 13:00"; ev scratch-amazon            # fix-x MERGED -> OPEN post_fix -> the hook fires
check "post-fix: back to OPEN with post_fix, hook fired" bash -c "[[ \$(jq -r '.gaps[\"2026-11-07\"].post_fix' '$WALKAWAY_HOME/data/state/scratch-amazon.json') == true ]] && grep -q '^scratch-amazon command echo fix-hook {from} {to} 2026-11-07 2026-11-07$' '$WALKAWAY_HOME/triggers.log'"
at "2026-11-18 14:01"; ev scratch-amazon            # verify failed -> try 2
at "2026-11-18 15:02"; ev scratch-amazon            # verify failed -> need_operator -> operator rule 2
check "two hook triggers, then ESCALATED (high) naming the merged fix" bash -c "[[ \$(grep -c '^scratch-amazon ' '$WALKAWAY_HOME/triggers.log') -eq 2 ]] && grep -q \$'\thigh\tdata scratch-amazon: ESCALATED - scratch-amazon 2026-11-07 still 0/5 rows after fix fix-x merged and its hook re-pulled twice' '$WALKAWAY_HOME/logs/ntfy.log'"
check "no model call, no new plan, no new build" bash -c "diff -q '$W/stub-claude.log' '$W/stub-claude.log.before' >/dev/null && [[ \$(ls '$WALKAWAY_HOME/registry') == fix-x.json ]] && ! ls '$WALKAWAY_HOME/data-fixes/'*/handoff/build-plan-* >/dev/null 2>&1"
at "2026-11-18 15:04"; ev scratch-amazon
check "no further trigger or ntfy" bash -c "[[ \$(grep -c '^scratch-amazon ' '$WALKAWAY_HOME/triggers.log') -eq 2 && \$(grep -c 'data scratch-amazon: ESCALATED' '$WALKAWAY_HOME/logs/ntfy.log') -eq 1 ]]"
rm -rf "$W3"; export WALKAWAY_HOME="$W/home"

echo "O6 the model escalates (protected cause) -> ESCALATED with its one question"
at "2026-11-18 13:00"
fill scratch-daily 2026-11-01 2026-11-17 12; fill scratch-daily 2026-11-09 2026-11-09 0
echo '{"decision":"escalate","protected_hit":true,"needs_live_action":true,"confidence":"high","cause":"The pull needs a fresh login.","evidence":["session logged out"],"question":"The scratch pull is logged out since 11-09; can you log in again on the Mini?"}' > "$W/decisions/scratch-daily.json"
ev scratch-daily
check "ESCALATED (high) with the model's question" grep -q $'\thigh\tdata scratch-daily: ESCALATED - The scratch pull is logged out since 11-09; can you log in again on the Mini?$' "$WALKAWAY_HOME/logs/ntfy.log"
check "no plan, no build" bash -c "! ls '$WALKAWAY_HOME/data-fixes/scratch-daily-2026-11-18/handoff/'build-plan-* >/dev/null 2>&1 && [[ ! -f '$WALKAWAY_HOME/registry/fix-data-scratch-daily-20261118.json' ]]"

echo "O7 the operator exits without a decision -> ESCALATED once, never a loop"
W2=$(mktemp -d); export WALKAWAY_HOME="$W2/home"; mkdir -p "$WALKAWAY_HOME"
printf '#!/usr/bin/env bash\nexit 0\n' > "$W/silent-operator.sh"; chmod +x "$W/silent-operator.sh"
export WALKAWAY_DATA_OPERATOR="$W/silent-operator.sh"
at "2026-11-18 13:00"; ev scratch-daily
at "2026-11-18 13:02"; ev scratch-daily
at "2026-11-18 13:04"; ev scratch-daily
check "exactly one ESCALATED 'exited without a decision'" bash -c "[[ \$(grep -c 'data scratch-daily: ESCALATED - Data operator exited without a decision on scratch-daily 2026-11-09' '$WALKAWAY_HOME/logs/ntfy.log') -eq 1 ]]"
unset WALKAWAY_DATA_OPERATOR; rm -rf "$W2"; export WALKAWAY_HOME="$W/home"

echo ""
echo "Results: $PASS passed, $FAIL failed"
(( FAIL == 0 ))
