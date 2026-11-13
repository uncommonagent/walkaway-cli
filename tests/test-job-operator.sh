#!/usr/bin/env bash
# Job operator (lib/job-operator.sh) in a scratch world: real jobs.yaml predicates and real failure rows
# (tests/fixtures/jobs), owner repos = scratch repos, walkaway launches with the stub builder, claude -p replaced
# by a stub returning canned decisions, ntfy recorded to ntfy.log only. Retry paths are stubbed (echo).
# Exit 0 = all pass.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/.."
FX="${SCRIPT_DIR}/fixtures/jobs"
# shellcheck source=tests/drill/scratch.sh
source "${SCRIPT_DIR}/drill/scratch.sh"

W=$(mktemp -d)
export WALKAWAY_HOME="$W/home" WALKAWAY_NTFY_DISABLED=1 NTFY_TOPIC=job-op-test WALKAWAY_JOBS_REST_FIXTURES="$W/rest"
export WALKAWAY_BUILDER_CMD="${SCRIPT_DIR}/drill/stub-builder.sh" WALKAWAY_GH_CMD="${SCRIPT_DIR}/drill/gh-sim.sh" GH_SIM_DIR="$W/gh"
export WALKAWAY_OPERATOR_CMD="$W/stub-claude" WALKAWAY_LAUNCH_LOG_DIR="$W/logs" WALKAWAY_CLAUDE_PROJECTS="$W/none"
export WALKAWAY_JOBS_FILE="$W/jobs.yaml"
mkdir -p "$WALKAWAY_HOME/queue" "$W/logs" "$W/decisions" "$W/rest"
touch "$WALKAWAY_HOME/supervisor.enabled"

PASS=0
FAIL=0
check() { local label="$1"; shift; if "$@"; then echo "  PASS: $label"; PASS=$((PASS + 1)); else echo "  FAIL: $label"; FAIL=$((FAIL + 1)); fi; }
at() { TZ=America/New_York date -j -f '%Y-%m-%d %H:%M' "$1" +%s; }
st() { jq -r ".$2 // empty" "$WALKAWAY_HOME/jobs/state/$1.json"; }
ntfy() { cat "$WALKAWAY_HOME/logs/ntfy.log" 2>/dev/null | grep -c "job $1: $2 - "; }
rest() { mkdir -p "$W/rest/$1"; if [[ -f "$3" ]]; then cp "$3" "$W/rest/$1/$2.json"; else printf '%s' "$3" > "$W/rest/$1/$2.json"; fi; }
fail_job() { # job date-time: put the job in FAILED the way the job watch does (state + failed_detail)
  bash -c "source '$ROOT/lib/jobs.sh'; jstate_update '$1' '.date = \$d | .state = \"FAILED\" | .failed_detail = \$f | .since = 0' --arg d '$2' --arg f 'not OK by window end (test)'"
}
diagnose() { WALKAWAY_JOBS_NOW=$(at "$2 12:01") bash "$ROOT/lib/job-operator.sh" diagnose "$1" "$2" >> "$W/jop.log" 2>&1; }

cleanup() {
  local f p
  for f in "$WALKAWAY_HOME"/registry/*.json; do
    [[ -f "$f" ]] || continue
    for p in $(jq -r '.builder_pid, .watcher_pid | select(. != null)' "$f"); do pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null; done
  done
  [[ -n "${KEEP_WORK:-}" ]] && echo "kept $W" || rm -rf "$W"
}
trap cleanup EXIT

# claude stub: the decision for the job named on the task's "Job: <name> (" line.
cat > "$W/stub-claude" <<EOF
#!/usr/bin/env bash
job=\$(printf '%s\n' "\$2" | sed -n 's/^Job: \([a-z0-9-]*\) (.*/\1/p' | head -1)
echo "\$(date +%T) stub-claude \$job cwd=\$(pwd)" >> "$W/stub-claude.log"
jq -c '{structured_output: .}' "$W/decisions/\$job.json"
EOF
chmod +x "$W/stub-claude"

# Scratch owner repos; the real jobs.yaml with owner repos and retry paths pointed at the scratch world.
R1=$(drill_make_repo "$W/repos" audrey-scratch)
R2=$(drill_make_repo "$W/repos" throughline-scratch)
drill_set_modes "$R1" fix-bf-daily-20261113 work
WALKAWAY_JOBS_FILE="$ROOT/jobs.yaml" bash -c "source '$ROOT/lib/jobs.sh'; jobs_config" |
  jq --arg r1 "$R1" --arg r2 "$R2" --arg retry "echo retried >> '$W/retry.log'" '
    .jobs |= map(if .owner_repo | test("audrey") then .owner_repo = $r1 else .owner_repo = $r2 end
                 | if .name == "showingtime" then .retry.command = $retry else . end)' > "$W/jobs.yaml"

FIX_DECISION='{"decision":"fix","protected_hit":false,"needs_live_action":false,"confidence":"high",
 "cause":"Deals Hub capture race: runDaily waits 15 s for the listDealsExports call, the page fires it later, the node fallback returns 39 deals and drafts 0/1 (bf_runs 11:30Z/12:06Z/12:43Z).",
 "evidence":["bf_runs 2026-11-13T11:30:35Z ok=false deals 45 from node drafts 0/1","extension/bf-lists-lib.js:1059 deals capture"],
 "fix":{"title":"BF daily Deals Hub capture wait","goal":"BF daily captures Deals Hub on the first attempt.",
   "what_to_build":["extension/bf-lists-lib.js: wait for listDealsExports up to 60 s with page-ready signal"],
   "acceptance_criteria":[{"id":"AC1","text":"replayed 11/13 capture timing yields dealshub source","evidence_file":"handoff/fix-bf-daily-20261113-evidence/replay.txt"}],
   "regression_fixture":"11/13 bf_runs rows 11:30Z-12:43Z (node fallback, drafts 0/1)",
   "files_expected":["extension/bf-lists-lib.js","tests/bf-lists-capture.test.ts"],
   "do_not_build":["No change to the publish path"],"stop_rules":["Stop if the fix needs a live list write"]}}'

echo "J1 FAILED bf-daily, repo free -> incident + template-v2 plan + fix build launched (FIXING)"
rest bf-daily runs "$FX/bf-1113-failures.json"
echo "$FIX_DECISION" > "$W/decisions/bf-daily.json"
fail_job bf-daily 2026-11-13
diagnose bf-daily 2026-11-13
WS="$WALKAWAY_HOME/job-fixes/bf-daily-2026-11-13/handoff"
INC="$WS/job-incident-bf-daily-2026-11-13.md"
PLAN="$WS/build-plan-fix-bf-daily-20261113.md"
check "claude ran read-only in the owner repo" grep -q "stub-claude bf-daily cwd=$R1\$" "$W/stub-claude.log"
check "incident file: cause + evidence + real rows" bash -c "grep -q '^## Cause' '$INC' && grep -q 'Deals Hub capture race' '$INC' && grep -q '2026-11-13T12:43:36' '$INC'"
for sec in "## Feature name" "## Branch name" "## Repo" "## Goal" "## Non-goals" "## Evidence" "## Decisions" "## Quality rules" \
           "## Source of truth" "## Acceptance criteria" "## Gate checklist" "## Escalate to Jim" "## Expected files touched" \
           "## Phases" "## Do NOT build" "## Stop rules"; do
  grep -q "^$sec" "$PLAN" || echo "  missing section: $sec"
done
check "plan has every template-v2 section" bash -c "for s in '## Feature name' '## Branch name' '## Repo' '## Goal' '## Non-goals' '## Evidence' '## Decisions' '## Quality rules' '## Source of truth' '## Acceptance criteria' '## Gate checklist' '## Escalate to Jim' '## Expected files touched' '## Phases' '## Do NOT build' '## Stop rules'; do grep -q \"^\$s\" '$PLAN' || exit 1; done"
check "plan cites the Showrunner quality-rules file" grep -q 'quality-rules/showrunner-lists.md' "$PLAN"
check "plan parses: feature, branch, repo = owner repo" bash -c "[[ \$(bash '$ROOT/lib/parse-plan.sh' '$PLAN' | tr '\n' ' ') == 'FEATURE_NAME=fix-bf-daily-20261113 BRANCH_NAME=feature/fix-bf-daily-20261113 REPO_PATH=$R1 ' ]]"
check "fix build launched and registered in the owner repo" bash -c "[[ \$(jq -r .repo '$WALKAWAY_HOME/registry/fix-bf-daily-20261113.json') == '$R1' ]] && kill -0 \$(jq -r .builder_pid '$WALKAWAY_HOME/registry/fix-bf-daily-20261113.json')"
check "job FIXING, one ntfy naming the launch" bash -c "[[ \$(jq -r .state '$WALKAWAY_HOME/jobs/state/bf-daily.json') == FIXING ]] && [[ \$(grep -c 'job bf-daily: FIXING - cause: Deals Hub capture race.*fix build fix-bf-daily-20261113 launched (builder pid [0-9]*)' '$WALKAWAY_HOME/logs/ntfy.log') -eq 1 ]]"
check "queue entry consumed by the launch" bash -c "! grep -q fix-bf-daily '$WALKAWAY_HOME/queue/audrey-scratch.txt'"

echo "J2 one auto-fix per job per day: a second FAILED the same day escalates, no second build"
fail_job bf-daily 2026-11-13
diagnose bf-daily 2026-11-13
check "ESCALATED: already ran today" grep -q 'job bf-daily: ESCALATED - .*a fix build for bf-daily already ran today (fix-bf-daily-20261113)' "$WALKAWAY_HOME/logs/ntfy.log"
check "claude not asked again" [ "$(grep -c 'stub-claude bf-daily' "$W/stub-claude.log")" -eq 1 ]

echo "J3 FAILED with a protected cause -> ESCALATED with ONE question, no plan, no queue"
rest cc-optin-am run "$FX/cc-am-1104-halted.json"
echo '{"decision":"fix","protected_hit":false,"needs_live_action":true,"confidence":"high","cause":"Amazon changed the bulk-accept response; parse fails at batch 0.","evidence":["cc_optin_runs 2026-11-04 HALTED unrecognized submit response (batch 0)"],"question":"CC opt-in AM halted on a new Amazon submit response; verifying a parser fix needs one live opt-in batch - allow it, yes/no?","fix":{"what_to_build":["parser"]}}' > "$W/decisions/cc-optin-am.json"
fail_job cc-optin-am 2026-11-04
diagnose cc-optin-am 2026-11-04
check "ESCALATED with the model's one question (priority high)" grep -q $'\thigh\tjob cc-optin-am: ESCALATED - CC opt-in AM halted on a new Amazon submit response; verifying a parser fix needs one live opt-in batch - allow it, yes/no?$' "$WALKAWAY_HOME/logs/ntfy.log"
check "incident written with the protected reason" grep -q 'ESCALATED (protected job: verifying the fix needs its live action)' "$WALKAWAY_HOME/job-fixes/cc-optin-am-2026-11-04/handoff/job-incident-cc-optin-am-2026-11-04.md"
check "no plan, no queue entry, no build" bash -c "! ls '$WALKAWAY_HOME/job-fixes/cc-optin-am-2026-11-04/handoff/'build-plan-* >/dev/null 2>&1 && ! grep -q cc-optin '$WALKAWAY_HOME/queue/'*.txt 2>/dev/null && [[ ! -f '$WALKAWAY_HOME/registry/fix-cc-optin-am-20261104.json' ]]"
echo '{"decision":"fix","protected_hit":true,"needs_live_action":false,"confidence":"high","cause":"x","evidence":[],"fix":{"what_to_build":["y"]}}' > "$W/decisions/spc.json"
rest spc run '[{"run_date":"2026-11-13","status":"UNFINISHED","listed":5,"accepted":0,"failed":0,"remaining":5,"detail":"login wall","updated_at":"2026-11-13T23:00:00Z"}]'
fail_job spc 2026-11-13
diagnose spc 2026-11-13
check "protected_hit without a question -> generated one-line question" grep -q 'job spc: ESCALATED - spc failed 2026-11-13 (not OK by window end (test)): protected action. How should it be handled?' "$WALKAWAY_HOME/logs/ntfy.log"
echo '{"decision":"fix","protected_hit":false,"needs_live_action":false,"confidence":"medium","cause":"maybe","evidence":[],"fix":{"what_to_build":["y"]}}' > "$W/decisions/realtea-generate.json"
fail_job realtea-generate 2026-11-16
diagnose realtea-generate 2026-11-16
check "medium confidence never auto-fixes" grep -q 'job realtea-generate: ESCALATED - .*confidence medium' "$WALKAWAY_HOME/logs/ntfy.log"

echo "J4 repo busy -> fix plan queued behind the active build; launched by the normal post-merge queue"
sleep 600 > /dev/null 2>&1 &
bash -c "source '$ROOT/lib/registry.sh'; registry_register busy-build '$R2' '$R2' '$R2/handoff/x.md' feature/busy '$!' '' '' false"
echo "${FIX_DECISION//bf-daily/showingtime}" > "$W/decisions/showingtime.json"
rest showingtime show '[]'
rest showingtime attempts '[{"outcome":"login_failed","trigger":"alarm","started_at":"2026-11-13T11:45:00Z","rows":0,"dates_failed":8}]'
fail_job showingtime 2026-11-13
diagnose showingtime 2026-11-13
check "queued behind busy-build, not launched" bash -c "grep -q 'build-plan-fix-showingtime-20261113.md' '$WALKAWAY_HOME/queue/throughline-scratch.txt' && [[ ! -f '$WALKAWAY_HOME/registry/fix-showingtime-20261113.json' ]]"
check "FIXING ntfy says queued" grep -q 'job showingtime: FIXING - .*fix build fix-showingtime-20261113 queued behind busy-build in throughline-scratch' "$WALKAWAY_HOME/logs/ntfy.log"
WALKAWAY_JOBS_NOW=$(at "2026-11-13 12:05") bash "$ROOT/lib/job-operator.sh" progress showingtime >> "$W/jop.log" 2>&1
check "progress while queued" [ "$(st showingtime last_action)" == "fix build fix-showingtime-20261113 queued (not launched yet)" ]

echo "J5 fix MERGED -> the job's retry path runs exactly once -> next check OK -> one resolved ntfy"
bash -c "source '$ROOT/lib/registry.sh'; registry_register fix-showingtime-20261113 '$R2' '$R2' '$R2/handoff/x.md' feature/fix-showingtime-20261113 '' '' '' false; registry_update fix-showingtime-20261113 '.state = \"MERGED\"'"
for _ in 1 2; do WALKAWAY_JOBS_NOW=$(at "2026-11-13 12:20") bash "$ROOT/lib/job-operator.sh" progress showingtime >> "$W/jop.log" 2>&1; done
check "retry path ran exactly once" [ "$(wc -l < "$W/retry.log" | tr -d ' ')" -eq 1 ]
check "last action records the retry" bash -c "[[ \$(jq -r .last_action '$WALKAWAY_HOME/jobs/state/showingtime.json') == 'fix fix-showingtime-20261113 merged; retry path triggered (rc 0); confirming OK' ]]"
rest showingtime show '[{"obs_date":"2026-11-12","showings":2390,"source":"showingtime","first_seen_at":"2026-11-13T17:25:00Z"}]'
for t in "2026-11-13 12:30" "2026-11-13 12:32"; do WALKAWAY_JOBS_NOW=$(at "$t") bash "$ROOT/lib/jobs.sh" tick >> "$W/jop.log" 2>&1; done
check "job OK, exactly one resolved ntfy" bash -c "[[ \$(jq -r .state '$WALKAWAY_HOME/jobs/state/showingtime.json') == OK ]] && [[ \$(grep -c 'job showingtime: OK - resolved: 2026-11-12 total showings=2390' '$WALKAWAY_HOME/logs/ntfy.log') -eq 1 ]]"
bash -c "source '$ROOT/lib/registry.sh'; registry_update fix-bf-daily-20261113 '.state = \"MERGED\"'"
WALKAWAY_JOBS_NOW=$(at "2026-11-13 12:20") bash "$ROOT/lib/job-operator.sh" progress bf-daily >> "$W/jop.log" 2>&1
check "no retry path (bf-daily) -> waits for the job's next run" bash -c "[[ \$(jq -r .last_action '$WALKAWAY_HOME/jobs/state/bf-daily.json') == *'no safe retry path - confirming on the job'* ]]"

echo "J6 exactly one ntfy per transition"
for j in bf-daily cc-optin-am spc realtea-generate showingtime; do
  dup=$(cut -f4 "$WALKAWAY_HOME/logs/ntfy.log" | grep "^job $j: " | cut -d' ' -f3 | sort | uniq -d)
  [[ -n "$dup" && "$j" != "bf-daily" ]] && echo "  duplicate $j transition: $dup"
done
check "bf-daily: FIXING once, ESCALATED once" [ "$(ntfy bf-daily FIXING)/$(ntfy bf-daily ESCALATED)" == "1/1" ]
check "showingtime: FIXING once, OK once" [ "$(ntfy showingtime FIXING)/$(ntfy showingtime OK)" == "1/1" ]
check "cc-optin-am / spc / realtea-generate: ESCALATED once each" [ "$(ntfy cc-optin-am ESCALATED)$(ntfy spc ESCALATED)$(ntfy realtea-generate ESCALATED)" == "111" ]

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
