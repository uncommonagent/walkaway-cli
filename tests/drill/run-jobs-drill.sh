#!/usr/bin/env bash
# AC3 live drill for job watching (supervisor-v2-jobs). Real supervisor ticks (lib/supervisor.sh tick with job
# watching on) in a scratch $WALKAWAY_HOME, time travel via WALKAWAY_JOBS_NOW, REAL headless `claude -p`
# diagnoses, REAL ntfy pushes to a drill topic (captured via the ntfy JSON poll API). Job rows are fixtures
# (tests/fixtures/jobs, real rows captured read-only) - nothing reads or writes the live job tables.
#
# Owner repos are throwaway shared clones (audrey-ops-platform at 7da72ae = before the 11/13 Deals Hub fix,
# throughline-app at origin/main) whose origin is repointed at a scratch bare repo, and a registered busy build
# holds the audrey slot, so the fix plan is QUEUED and never launched: nothing can reach a real remote or repo.
#
#   1  07:45  bf-daily 3 failed attempts (11/13 rows) + extension tracking_offsite error -> RETRYING, no ntfy
#   2  08:20  extension recovered on its own retry                                    -> OK, no ntfy
#   3  12:01  bf-daily window passed -> FAILED ntfy -> claude diagnosis -> incident + template-v2 fix plan queued
#   4  12:46  showingtime missing + OTP timeout (2FA = PROTECTED) -> FAILED -> claude -> ESCALATED, one question
#   5  13:00  bf-daily recovered row                                                  -> OK resolved, one ntfy
# Evidence: handoff/supervisor-v2-jobs-evidence/ac3-drill/.
#
#   tests/drill/run-jobs-drill.sh            run the drill
#   tests/drill/run-jobs-drill.sh --clean    remove the scratch world

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FX="$ROOT/tests/fixtures/jobs"
WORK="$HERE/work-jobs"
EVID="$ROOT/handoff/supervisor-v2-jobs-evidence/ac3-drill"
TOPIC="${DRILL_TOPIC:-jim-walkaway-jobs-drill-$(openssl rand -hex 4)}"
AUDREY_SRC="${DRILL_AUDREY_SRC:-$HOME/Projects/audrey-ops-platform}"
THROUGHLINE_SRC="${DRILL_THROUGHLINE_SRC:-$HOME/Projects/Throughline/throughline-app}"

if [[ "${1:-}" == "--clean" ]]; then
  for f in "$WORK"/home/registry/*.json; do [[ -f "$f" ]] && kill "$(jq -r .builder_pid "$f")" 2>/dev/null; done
  rm -rf "$WORK"; echo "jobs drill torn down"; exit 0
fi

rm -rf "$WORK" "$EVID"
mkdir -p "$WORK/rest" "$WORK/logs" "$EVID"
T0=$(date +%s)
TRANSCRIPT="$EVID/drill-transcript.txt"
say() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$TRANSCRIPT"; }
PASS=0
FAIL=0
check() { local label="$1"; shift; if "$@"; then say "PASS: $label"; PASS=$((PASS + 1)); else say "FAIL: $label"; FAIL=$((FAIL + 1)); fi; }

export WALKAWAY_HOME="$WORK/home" NTFY_TOPIC="$TOPIC" WALKAWAY_HEARTBEAT_HOURS="" WALKAWAY_JOBS_FILE="$WORK/jobs.yaml"
export WALKAWAY_JOBS_REST_FIXTURES="$WORK/rest" WALKAWAY_GH_CMD="$HERE/gh-sim.sh" GH_SIM_DIR="$WORK/gh"
export WALKAWAY_CLAUDE_PROJECTS="$WORK/none" WALKAWAY_LAUNCH_LOG_DIR="$WORK/logs"
# drill-busy is a sleep standing in for a builder: never let it read as STALLED while claude diagnoses.
export WALKAWAY_STALL_SECS=86400
unset WALKAWAY_NTFY_DISABLED WALKAWAY_OPERATOR_CMD WALKAWAY_JOB_OPERATOR
mkdir -p "$WALKAWAY_HOME"
touch "$WALKAWAY_HOME/supervisor.enabled" "$WALKAWAY_HOME/jobs.enabled"

say "jobs drill start: topic $TOPIC, home $WALKAWAY_HOME"

# ── scratch owner repos ──────────────────────────────────────────────────────
scratch_clone() { # src commit name -> path
  local src="$1" commit="$2" name="$3" dst
  dst="$WORK/$name"
  git init -q --bare "$WORK/$name-origin.git"
  git clone -q --shared --no-checkout "$src" "$dst"
  git -C "$dst" checkout -q -B main "$commit"
  git -C "$dst" remote set-url origin "$WORK/$name-origin.git"
  git -C "$dst" push -q origin main 2>/dev/null
  git -C "$dst" remote set-head origin main
  echo "$dst"
}
AUD=$(scratch_clone "$AUDREY_SRC" 7da72ae audrey-ops-platform-drill)
THR=$(scratch_clone "$THROUGHLINE_SRC" "$(git -C "$THROUGHLINE_SRC" rev-parse origin/main)" throughline-app-drill)
say "scratch owner repos: $AUD (7da72ae, pre Deals Hub fix), $THR; origins repointed to $WORK/*-origin.git"

sleep 3600 > /dev/null 2>&1 &
BUSY=$!
bash -c "source '$ROOT/lib/registry.sh'; registry_register drill-busy '$AUD' '$AUD' '$AUD/handoff/build-plan-drill-busy.md' main '$BUSY' '' '' false" > /dev/null
say "drill-busy registered in $AUD (pid $BUSY): holds the one-builder slot so the fix plan queues"

# ── jobs config + fixture rows ───────────────────────────────────────────────
AGENT_LOG="$WORK/st-login-agent.log"
WALKAWAY_JOBS_FILE="$ROOT/jobs.yaml" bash -c "source '$ROOT/lib/jobs.sh'; jobs_config" |
  jq --arg aud "$AUD" --arg thr "$THR" --arg log "$AGENT_LOG" '
    .jobs |= map(if .owner_repo | test("audrey") then .owner_repo = $aud else .owner_repo = $thr end
      | if .name == "showingtime" then .check.logs.agent.path = $log | .diagnose.logs.agent_tail.path = $log
          | .retry.command = "echo drill: retry path not run" else . end)' > "$WORK/jobs.yaml"
rest() { mkdir -p "$WORK/rest/$1"; if [[ -f "$3" ]]; then cp "$3" "$WORK/rest/$1/$2.json"; else printf '%s' "$3" > "$WORK/rest/$1/$2.json"; fi; }
rest cc-optin-am run '[{"run_date":"2026-11-13","session":"am","status":"DONE","halted_reason":null,"export_rows":12384,"updated_at":"2026-11-13T16:25:19Z"}]'
rest spc run '[{"run_date":"2026-11-13","status":"ACCEPTED","listed":162,"accepted":162,"failed":0,"remaining":0,"updated_at":"2026-11-13T16:29:20Z"}]'
rest bf-daily runs "$FX/bf-1113-failures.json"
rest bf-daily runs_full "$FX/bf-1113-runs-full.json"
rest bf-daily daily_list '[]'
jq '(.[] | select(.report_type == "tracking_offsite")) |= (.last_error_at = "2026-11-13T13:05:00+00:00" | .last_success_at = "2026-11-12T20:00:00+00:00" | .last_error_message = "offsite pull failed: listReports timeout")' \
  "$FX/ext-state-1113.json" > "$WORK/ext-err.json"
rest extension-reports state "$WORK/ext-err.json"
rest showingtime show '[{"obs_date":"2026-11-12","showings":2390,"source":"showingtime","first_seen_at":"2026-11-13T11:45:43Z"}]'
rest showingtime attempts '[]'

at() { TZ=America/New_York date -j -f '%Y-%m-%d %H:%M' "2026-11-13 $1" +%s; }
tick() { say "supervisor tick @ 2026-11-13 $1 ET (time travel)"; WALKAWAY_JOBS_NOW=$(at "$1") bash "$ROOT/lib/supervisor.sh" tick >> "$WORK/supervisor.log" 2>&1; }
jst() { jq -r ".$2 // empty" "$WALKAWAY_HOME/jobs/state/$1.json" 2>/dev/null; }
jobntfy() { cat "$WALKAWAY_HOME/logs/ntfy.log" 2>/dev/null | grep -c "	job $1: "; }
wait_operator() { # job: wait (<= 30 min) for the real claude diagnosis to record its transition
  local i p
  for i in $(seq 1 360); do
    p=$(jst "$1" operator_pid)
    { [[ -z "$p" ]] || ! kill -0 "$p" 2>/dev/null; } && [[ "$(jst "$1" state)" != "FAILED" ]] && { say "$1 operator done after $((i * 5))s: $(jst "$1" state)"; return 0; }
    sleep 5
  done
  say "$1 operator still running after 30 min"
}

# ── 1: RETRYING, no alert ────────────────────────────────────────────────────
tick 07:45
check "bf-daily RETRYING at 07:45 (3 failed attempts inside the 12:00 window)" [ "$(jst bf-daily state)" == "RETRYING" ]
check "extension-reports RETRYING (tracking_offsite error < 2 h)" [ "$(jst extension-reports state)" == "RETRYING" ]
check "RETRYING sent no ntfy" [ "$(jobntfy bf-daily)$(jobntfy extension-reports)" == "00" ]

# ── 2: recovered on its own retry, no alert ──────────────────────────────────
rest extension-reports state "$FX/ext-state-1113.json"
tick 08:20
check "extension-reports OK after its own retry, no ntfy" [ "$(jst extension-reports state)/$(jobntfy extension-reports)" == "OK/0" ]

# ── 3: FAILED -> real diagnosis -> incident + fix plan queued ────────────────
tick 12:01
check "bf-daily FAILED at 12:01" bash -c "grep -q 'job bf-daily: FAILED - not OK by 12:00' '$WALKAWAY_HOME/logs/ntfy.log'"
wait_operator bf-daily
INC_BF="$WALKAWAY_HOME/job-fixes/bf-daily-2026-11-13/handoff/job-incident-bf-daily-2026-11-13.md"
PLAN_BF=$(ls "$WALKAWAY_HOME"/job-fixes/bf-daily-2026-11-13/handoff/build-plan-fix-bf-daily-*.md 2>/dev/null | head -1)
check "incident file written (cause + evidence)" bash -c "grep -q '^## Cause' '$INC_BF' && grep -q '^## Evidence' '$INC_BF'"
check "bf-daily FIXING: template-v2 fix plan queued behind drill-busy" bash -c "[[ '$(jst bf-daily state)' == FIXING ]] && grep -qxF '$PLAN_BF' '$WALKAWAY_HOME/queue/audrey-ops-platform-drill.txt'"
check "fix plan not launched (no registry entry)" bash -c "! ls '$WALKAWAY_HOME'/registry/fix-bf-daily-*.json > /dev/null 2>&1"
check "plan cites showrunner-lists.md and names the owner repo" bash -c "grep -q 'quality-rules/showrunner-lists.md' '$PLAN_BF' && grep -qF '$AUD' '$PLAN_BF'"

# ── 4: FAILED with a protected cause -> ESCALATED, one question ──────────────
rest showingtime show '[]'
rest showingtime attempts '[{"outcome":"otp_timeout","trigger":"alarm","started_at":"2026-11-13T11:31:12Z","rows":0,"dates_failed":8,"detail":"2FA prompt shown; no code arrived within 300 s"},{"outcome":"otp_timeout","trigger":"failed_retry","started_at":"2026-11-13T17:30:40Z","rows":0,"dates_failed":8,"detail":"2FA prompt shown; no code arrived within 300 s"}]'
cat > "$AGENT_LOG" <<'EOF'
2026-11-13 07:05:04 decision=ACT_OTP_TIMEOUT yesterday=2026-11-12 present=0 ext_last_outcome_today=otp_timeout
2026-11-13 07:11:09 recheck yesterday=2026-11-12 present=0 after gesture login: OTP screen, no code
EOF
tick 12:46
check "showingtime FAILED at 12:46 (after its 12:45 retry window)" bash -c "grep -q 'job showingtime: FAILED - not OK by 12:45' '$WALKAWAY_HOME/logs/ntfy.log'"
wait_operator showingtime
check "showingtime ESCALATED (protected: OTP/2FA), no fix plan" bash -c "[[ '$(jst showingtime state)' == ESCALATED ]] && ! ls '$WALKAWAY_HOME'/job-fixes/showingtime-2026-11-13/handoff/build-plan-* > /dev/null 2>&1"
Q=$(grep $'\tjob showingtime: ESCALATED - ' "$WALKAWAY_HOME/logs/ntfy.log" | cut -f4-)
say "escalation line: $Q"
check "ESCALATED is priority high and one line" bash -c "grep -q $'\thigh\tjob showingtime: ESCALATED - ' '$WALKAWAY_HOME/logs/ntfy.log' && [[ \$(grep -c 'job showingtime: ESCALATED' '$WALKAWAY_HOME/logs/ntfy.log') -eq 1 ]]"

# ── 5: resolution -> one ntfy ────────────────────────────────────────────────
rest bf-daily runs "$FX/bf-1113-recovered.json"
tick 13:00
tick 13:02
check "bf-daily OK, exactly one resolved ntfy" bash -c "[[ '$(jst bf-daily state)' == OK ]] && [[ \$(grep -c 'job bf-daily: OK - resolved' '$WALKAWAY_HOME/logs/ntfy.log') -eq 1 ]]"

# ── capture + verify ntfy ────────────────────────────────────────────────────
sleep 5
curl -s "https://ntfy.sh/$TOPIC/json?poll=1&since=$T0" > "$EVID/ntfy-poll.json"
cp "$WALKAWAY_HOME/logs/ntfy.log" "$EVID/ntfy-local.log"
jq -r 'select(.event == "message") | [(.time | strftime("%H:%M:%S")), (.priority // 3 | tostring), .message] | @tsv' "$EVID/ntfy-poll.json" > "$EVID/ntfy-poll-messages.tsv"
say "ntfy poll: $(wc -l < "$EVID/ntfy-poll-messages.tsv" | tr -d ' ') messages on $TOPIC; local sends: $(wc -l < "$EVID/ntfy-local.log" | tr -d ' ')"
check "ntfy poll == local send log (1:1)" bash -c "[[ \"\$(cut -f3- '$EVID/ntfy-poll-messages.tsv' | sort)\" == \"\$(cut -f4- '$EVID/ntfy-local.log' | sort)\" ]]"
check "no transition repeated back-to-back per job/build" bash -c "[[ -z \$(cut -f3- '$EVID/ntfy-poll-messages.tsv' | awk -F' - ' '{n=split(\$1, a, \": \"); k=a[1]; s=a[2]; if (last[k] == s) print; last[k] = s}') ]]"
check "job lines are exactly: bf FAILED, bf FIXING, st FAILED, st ESCALATED, bf OK" bash -c "[[ \"\$(cut -f3 '$EVID/ntfy-poll-messages.tsv' | grep '^job ' | sed -E 's/^(job [a-z-]+: [A-Z]+) - .*/\1/' | tr '\n' '|')\" == 'job bf-daily: FAILED|job bf-daily: FIXING|job showingtime: FAILED|job showingtime: ESCALATED|job bf-daily: OK|' ]]"

# ── archive ──────────────────────────────────────────────────────────────────
cp "$INC_BF" "$EVID/" 2>/dev/null
[[ -n "$PLAN_BF" ]] && cp "$PLAN_BF" "$EVID/"
cp "$WALKAWAY_HOME"/job-fixes/showingtime-2026-11-13/handoff/job-incident-*.md "$EVID/" 2>/dev/null
mkdir -p "$EVID/state"; cp "$WALKAWAY_HOME"/jobs/state/*.json "$EVID/state/"
cp "$WALKAWAY_HOME/queue/audrey-ops-platform-drill.txt" "$EVID/queue-audrey-ops-platform-drill.txt" 2>/dev/null
grep -h 'jobs:' "$WORK/supervisor.log" > "$EVID/supervisor-job-transitions.log" 2>/dev/null
cat "$WALKAWAY_HOME"/logs/job-operator-*.log > "$EVID/job-operator.log" 2>/dev/null
WALKAWAY_JOBS_NOW=$(at 13:02) bash "$ROOT/walkaway.sh" status > "$EVID/walkaway-status-drill.txt" 2>&1
# Scratch paths in archived files are under tests/drill/work-jobs (gitignored); nothing else is copied.
kill "$BUSY" 2>/dev/null

say "jobs drill done: $PASS passed, $FAIL failed (topic $TOPIC)"
[[ "$FAIL" -eq 0 ]]
