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
#   1  07:45  failing attempts inside their windows (drill-export, bf-daily 11/13 rows, extension error) -> RETRYING,
#             no ntfy
#   2  08:20  extension recovered on its own retry                                    -> OK, no ntfy
#   3  09:01  drill-export (throwaway job, scratch repo with a real code bug the rows point at) -> FAILED -> claude
#             diagnosis -> incident + template-v2 fix plan QUEUED behind the busy build -> FIXING
#   4  12:01  bf-daily (real 11/13 rows, audrey clone before the Deals Hub fix) -> FAILED -> claude -> its decision
#             (FIXING or ESCALATED) is recorded; the 12:14 run escalated: proving the fix needs live Amazon writes
#   5  12:46  showingtime missing + OTP timeout (2FA = PROTECTED) -> FAILED -> claude -> ESCALATED, ONE question
#   6  13:00  the drill-export fix "merges" -> its retry path runs exactly once; 13:02 rows OK -> OK resolved (one
#             ntfy); bf-daily recovered row -> OK resolved (one ntfy)
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

# Throwaway nightly-export job: a scratch repo whose runner has a real bug (reads r.ammount, the column is amount).
EXP="$WORK/nightly-export-drill"
git init -q --bare "$WORK/nightly-export-drill-origin.git"
git init -q -b main "$EXP"
mkdir -p "$EXP/scripts" "$EXP/data" "$EXP/handoff"
cat > "$EXP/scripts/nightly-export.js" <<'JS'
// Nightly export (throwaway drill repo): sums yesterday's order amounts from data/orders.csv and records one
// export_runs row {ok, total, error}. Scheduled 06:00 ET with retries every 30 min until 09:00.
const fs = require('fs')

function readOrders(path) {
  const [head, ...lines] = fs.readFileSync(path, 'utf8').trim().split('\n')
  const cols = head.split(',')
  return lines.map((l) => Object.fromEntries(l.split(',').map((v, i) => [cols[i], v])))
}

function total(rows) {
  return rows.reduce((sum, r) => sum + parseFloat(r.ammount), 0)
}

function run() {
  const t = total(readOrders('data/orders.csv'))
  if (Number.isNaN(t)) throw new Error('total is NaN (scripts/nightly-export.js:18)')
  return { ok: true, total: Math.round(t * 100) / 100 }
}

module.exports = { readOrders, total, run }
JS
printf 'id,customer,amount\n1,acme,12.50\n2,globex,30.25\n3,initech,7.00\n' > "$EXP/data/orders.csv"
printf '# nightly-export (drill throwaway)\nRunner: scripts/nightly-export.js. Writes export_runs.\n' > "$EXP/README.md"
git -C "$EXP" add -A
git -C "$EXP" -c user.name=drill -c user.email=drill@example.invalid commit -qm "nightly export runner"
git -C "$EXP" remote add origin "$WORK/nightly-export-drill-origin.git"
git -C "$EXP" push -q -u origin main 2>/dev/null
git -C "$EXP" remote set-head origin main

sleep 3600 > /dev/null 2>&1 &
BUSY=$!
bash -c "source '$ROOT/lib/registry.sh'; registry_register drill-busy '$EXP' '$EXP' '$EXP/handoff/build-plan-drill-busy.md' main '$BUSY' '' '' false" > /dev/null
say "drill-busy registered in $EXP (pid $BUSY): holds the one-builder slot so the fix plan queues"

# ── jobs config + fixture rows ───────────────────────────────────────────────
AGENT_LOG="$WORK/st-login-agent.log"
WALKAWAY_JOBS_FILE="$ROOT/jobs.yaml" bash -c "source '$ROOT/lib/jobs.sh'; jobs_config" |
  jq --arg aud "$AUD" --arg thr "$THR" --arg log "$AGENT_LOG" --arg exp "$EXP" --arg retrylog "$WORK/retry.log" '
    .jobs |= map(if .owner_repo | test("audrey") then .owner_repo = $aud else .owner_repo = $thr end
      | if .name == "showingtime" then .check.logs.agent.path = $log | .diagnose.logs.agent_tail.path = $log
          | .retry.command = "echo drill: retry path not run" else . end)
    | .jobs += [{name: "drill-export", title: "Nightly export (drill throwaway)", enabled: true, owner_repo: $exp,
        kind: "daily", window: {start: "06:00", end: "09:00"}, retry_end: "09:00", protected: false, quality_rules: null,
        retry: {command: ("echo retried >> " + $retrylog), note: "drill: records the retry"},
        check: {source: "audrey", queries: {runs: "export_runs?select=started_at,ok,total,error&run_date=eq.{date}&order=started_at.desc"},
          predicate: "(.q.runs | map(select(.ok == true))) as $ok | (.q.runs | map(select(.ok == false))) as $bad | if ($ok | length) > 0 then {verdict: \"ok\", detail: \"total \\($ok[0].total) at \\($ok[0].started_at)\"} elif ($bad | length) > 0 then {verdict: \"retrying\", detail: \"\\($bad | length) failed attempt(s); latest \\($bad[0].started_at): \\($bad[0].error)\"} else {verdict: \"pending\", detail: \"no run yet\"} end"},
        diagnose: {notes: ["Runner: scripts/nightly-export.js (run -> total -> readOrders); input data/orders.csv"]}}]' \
  > "$WORK/jobs.yaml"
rest() { mkdir -p "$WORK/rest/$1"; if [[ -f "$3" ]]; then cp "$3" "$WORK/rest/$1/$2.json"; else printf '%s' "$3" > "$WORK/rest/$1/$2.json"; fi; }
rest cc-optin-am run '[{"run_date":"2026-11-13","session":"am","status":"DONE","halted_reason":null,"export_rows":12384,"updated_at":"2026-11-13T16:25:19Z"}]'
rest spc run '[{"run_date":"2026-11-13","status":"ACCEPTED","listed":162,"accepted":162,"failed":0,"remaining":0,"updated_at":"2026-11-13T16:29:20Z"}]'
rest bf-daily runs "$FX/bf-1113-failures.json"
rest bf-daily runs_full "$FX/bf-1113-runs-full.json"
rest bf-daily daily_list '[]'
jq '(.[] | select(.report_type == "tracking_offsite")) |= (.last_error_at = "2026-11-13T13:05:00+00:00" | .last_success_at = "2026-11-12T20:00:00+00:00" | .last_error_message = "offsite pull failed: listReports timeout")' \
  "$FX/ext-state-1113.json" > "$WORK/ext-err.json"
rest extension-reports state "$WORK/ext-err.json"
rest showingtime show '[]'
rest showingtime attempts '[]'
rest drill-export runs '[{"started_at":"2026-11-13T12:00:04Z","ok":false,"total":null,"error":"total is NaN (scripts/nightly-export.js:18)"},{"started_at":"2026-11-13T11:30:03Z","ok":false,"total":null,"error":"total is NaN (scripts/nightly-export.js:18)"},{"started_at":"2026-11-13T11:00:02Z","ok":false,"total":null,"error":"total is NaN (scripts/nightly-export.js:18)"}]'

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
check "drill-export RETRYING at 07:45 (3 failed attempts inside the 09:00 window)" [ "$(jst drill-export state)" == "RETRYING" ]
check "showingtime PENDING (missing, no session yet)" [ "$(jst showingtime state)" == "PENDING" ]
check "extension-reports RETRYING (tracking_offsite error < 2 h)" [ "$(jst extension-reports state)" == "RETRYING" ]
check "RETRYING/PENDING sent no ntfy" [ "$(jobntfy bf-daily)$(jobntfy extension-reports)$(jobntfy drill-export)$(jobntfy showingtime)" == "0000" ]

# ── 2: recovered on its own retry, no alert ──────────────────────────────────
rest extension-reports state "$FX/ext-state-1113.json"
tick 08:20
check "extension-reports OK after its own retry, no ntfy" [ "$(jst extension-reports state)/$(jobntfy extension-reports)" == "OK/0" ]

# ── 3: FAILED -> real diagnosis -> incident + fix plan queued ────────────────
tick 09:01
check "drill-export FAILED at 09:01" bash -c "grep -q 'job drill-export: FAILED - not OK by 09:00' '$WALKAWAY_HOME/logs/ntfy.log'"
wait_operator drill-export
INC_EX="$WALKAWAY_HOME/job-fixes/drill-export-2026-11-13/handoff/job-incident-drill-export-2026-11-13.md"
PLAN_EX=$(ls "$WALKAWAY_HOME"/job-fixes/drill-export-2026-11-13/handoff/build-plan-fix-drill-export-*.md 2>/dev/null | head -1)
say "drill-export decision: $(sed -n '/^## Decision/{n;p;}' "$INC_EX" 2>/dev/null)"
check "incident file written (cause + evidence)" bash -c "grep -q '^## Cause' '$INC_EX' && grep -q '^## Evidence' '$INC_EX'"
check "drill-export FIXING: template-v2 fix plan queued behind drill-busy" bash -c "[[ '$(jst drill-export state)' == FIXING && -n '$PLAN_EX' ]] && grep -qxF '$PLAN_EX' '$WALKAWAY_HOME/queue/nightly-export-drill.txt'"
check "fix plan not launched (no registry entry)" bash -c "! ls '$WALKAWAY_HOME'/registry/fix-drill-export-*.json > /dev/null 2>&1"
check "plan has the template-v2 sections and names the owner repo" bash -c "for s in '## Feature name' '## Branch name' '## Repo' '## Goal' '## Evidence' '## Quality rules' '## Source of truth' '## Acceptance criteria' '## Gate checklist' '## Escalate to Jim' '## Phases' '## Do NOT build' '## Stop rules'; do grep -q \"^\$s\" '$PLAN_EX' || exit 1; done; grep -qF '$EXP' '$PLAN_EX'"

# ── 4: real 11/13 BF rows -> real diagnosis; the decision is recorded (FIXING or ESCALATED) ──
tick 12:01
check "bf-daily FAILED at 12:01" bash -c "grep -q 'job bf-daily: FAILED - not OK by 12:00' '$WALKAWAY_HOME/logs/ntfy.log'"
wait_operator bf-daily
INC_BF="$WALKAWAY_HOME/job-fixes/bf-daily-2026-11-13/handoff/job-incident-bf-daily-2026-11-13.md"
say "bf-daily decision: $(sed -n '/^## Decision/{n;p;}' "$INC_BF" 2>/dev/null)"
check "bf-daily resolved by the operator into FIXING or ESCALATED (one line)" bash -c "[[ '$(jst bf-daily state)' == FIXING || '$(jst bf-daily state)' == ESCALATED ]] && [[ \$(grep -cE 'job bf-daily: (FIXING|ESCALATED) - ' '$WALKAWAY_HOME/logs/ntfy.log') -eq 1 ]]"

# ── 5: FAILED with a protected cause -> ESCALATED, one question ──────────────
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

# ── 6: fix merged -> retry path once -> resolution, one ntfy each ────────────
FIXF=$(basename "$PLAN_EX" .md); FIXF=${FIXF#build-plan-}
bash -c "source '$ROOT/lib/registry.sh'; registry_register '$FIXF' '$EXP' '$EXP' '$PLAN_EX' 'feature/$FIXF' '' '' '' false; registry_update '$FIXF' '.state = \"MERGED\" | .last_action = \"drill: simulated merge\"'" > /dev/null
say "simulated merge of $FIXF (registry state MERGED)"
tick 13:00
check "retry path ran exactly once after the merge" bash -c "[[ \$(wc -l < '$WORK/retry.log' | tr -d ' ') -eq 1 ]]"
rest drill-export runs '[{"started_at":"2026-11-13T18:00:05Z","ok":true,"total":49.75,"error":null}]'
rest bf-daily runs "$FX/bf-1113-recovered.json"
tick 13:02
tick 13:04
check "retry did not run again" bash -c "[[ \$(wc -l < '$WORK/retry.log' | tr -d ' ') -eq 1 ]]"
check "drill-export OK, exactly one resolved ntfy" bash -c "[[ '$(jst drill-export state)' == OK ]] && [[ \$(grep -c 'job drill-export: OK - resolved: total 49.75' '$WALKAWAY_HOME/logs/ntfy.log') -eq 1 ]]"
check "bf-daily OK, exactly one resolved ntfy" bash -c "[[ '$(jst bf-daily state)' == OK ]] && [[ \$(grep -c 'job bf-daily: OK - resolved' '$WALKAWAY_HOME/logs/ntfy.log') -eq 1 ]]"

# ── capture + verify ntfy ────────────────────────────────────────────────────
sleep 5
curl -s "https://ntfy.sh/$TOPIC/json?poll=1&since=$T0" > "$EVID/ntfy-poll.json"
cp "$WALKAWAY_HOME/logs/ntfy.log" "$EVID/ntfy-local.log"
jq -r 'select(.event == "message") | [(.time | strftime("%H:%M:%S")), (.priority // 3 | tostring), .message] | @tsv' "$EVID/ntfy-poll.json" > "$EVID/ntfy-poll-messages.tsv"
say "ntfy poll: $(wc -l < "$EVID/ntfy-poll-messages.tsv" | tr -d ' ') messages on $TOPIC; local sends: $(wc -l < "$EVID/ntfy-local.log" | tr -d ' ')"
check "ntfy poll == local send log (1:1)" bash -c "[[ \"\$(cut -f3- '$EVID/ntfy-poll-messages.tsv' | sort)\" == \"\$(cut -f4- '$EVID/ntfy-local.log' | sort)\" ]]"
check "no transition repeated back-to-back per job/build" bash -c "[[ -z \$(cut -f3- '$EVID/ntfy-poll-messages.tsv' | awk -F' - ' '{n=split(\$1, a, \": \"); k=a[1]; s=a[2]; if (last[k] == s) print; last[k] = s}') ]]"
seq_of() { cut -f3 "$EVID/ntfy-poll-messages.tsv" | grep "^job $1: " | sed -E 's/^job [a-z-]+: ([A-Z]+) - .*/\1/' | tr '\n' ' '; }
say "polled transitions: drill-export [$(seq_of drill-export)] bf-daily [$(seq_of bf-daily)] showingtime [$(seq_of showingtime)] extension-reports [$(seq_of extension-reports)]"
check "drill-export: FAILED, FIXING, OK - one ntfy each" [ "$(seq_of drill-export)" == "FAILED FIXING OK " ]
check "showingtime: FAILED, ESCALATED - one ntfy each" [ "$(seq_of showingtime)" == "FAILED ESCALATED " ]
check "bf-daily: FAILED, FIXING|ESCALATED, OK - one ntfy each" bash -c "[[ '$(seq_of bf-daily)' == 'FAILED FIXING OK ' || '$(seq_of bf-daily)' == 'FAILED ESCALATED OK ' ]]"
check "RETRYING / PENDING / own-retry recovery never pinged (extension-reports silent)" [ -z "$(seq_of extension-reports)" ]

# ── archive ──────────────────────────────────────────────────────────────────
cp "$INC_EX" "$INC_BF" "$EVID/" 2>/dev/null
[[ -n "$PLAN_EX" ]] && cp "$PLAN_EX" "$EVID/"
cp "$WALKAWAY_HOME"/job-fixes/bf-daily-2026-11-13/handoff/build-plan-*.md "$EVID/" 2>/dev/null
cp "$WALKAWAY_HOME"/job-fixes/showingtime-2026-11-13/handoff/job-incident-*.md "$EVID/" 2>/dev/null
mkdir -p "$EVID/state"; cp "$WALKAWAY_HOME"/jobs/state/*.json "$EVID/state/"
cp "$WALKAWAY_HOME"/queue/*.txt "$EVID/" 2>/dev/null
cp "$WORK/retry.log" "$EVID/retry.log" 2>/dev/null
grep -h 'jobs:' "$WORK/supervisor.log" > "$EVID/supervisor-job-transitions.log" 2>/dev/null
cat "$WALKAWAY_HOME"/logs/job-operator-*.log > "$EVID/job-operator.log" 2>/dev/null
WALKAWAY_JOBS_NOW=$(at 13:04) bash "$ROOT/walkaway.sh" status > "$EVID/walkaway-status-drill.txt" 2>&1
# Scratch paths in archived files are under tests/drill/work-jobs (gitignored); nothing else is copied.
kill "$BUSY" 2>/dev/null
rm -rf "$AUD" "$THR"   # shared clones: drop the checkouts (the archived evidence keeps every decision)

say "jobs drill done: $PASS passed, $FAIL failed (topic $TOPIC)"
[[ "$FAIL" -eq 0 ]]
