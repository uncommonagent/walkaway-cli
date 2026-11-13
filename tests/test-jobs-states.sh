#!/usr/bin/env bash
# Job day-state machine on the real jobs.yaml predicates, fed real failure rows (tests/fixtures/jobs/, captured
# read-only on 2026-11-13) with time travel (WALKAWAY_JOBS_NOW). ntfy is recorded to ntfy.log only.
# The job operator is a stub that records its calls (job-operator behavior: tests/test-job-operator.sh).
# Exit 0 = all pass.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/.."
FX="${SCRIPT_DIR}/fixtures/jobs"
W=$(mktemp -d)
trap '[[ -n "${KEEP_WORK:-}" ]] && echo "kept $W" || rm -rf "$W"' EXIT
export WALKAWAY_HOME="$W/home" WALKAWAY_NTFY_DISABLED=1 NTFY_TOPIC=jobs-test WALKAWAY_JOBS_REST_FIXTURES="$W/rest"
export WALKAWAY_JOB_OPERATOR="$W/op-stub.sh"
mkdir -p "$W/rest"
# Stub job operator: records the call; "diagnose" ends in FIXING like a real fix decision (one ntfy).
cat > "$W/op-stub.sh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "\$WALKAWAY_HOME/op-calls.log"
[[ "\$1" == diagnose ]] || exit 0
source "$ROOT/lib/jobs.sh"
jobs_transition "\$2" FIXING "stub fix build queued"
jstate_update "\$2" 'del(.operator_pid)'
EOF
# Each scenario gets its own home: time-travelled ticks of one scenario never leak state into the next.
fresh() { export WALKAWAY_HOME="$W/home-$1"; mkdir -p "$WALKAWAY_HOME"; quiet; }

PASS=0
FAIL=0
check() { local label="$1"; shift; if "$@"; then echo "  PASS: $label"; PASS=$((PASS + 1)); else echo "  FAIL: $label"; FAIL=$((FAIL + 1)); fi; }
at() { TZ=America/New_York date -j -f '%Y-%m-%d %H:%M' "$1" +%s; }
tick() { WALKAWAY_JOBS_NOW=$(at "$1") bash "$ROOT/lib/jobs.sh" tick >> "$W/tick.log" 2>&1; sleep 0.2; }
st() { jq -r ".$2 // empty" "$WALKAWAY_HOME/jobs/state/$1.json"; }
ntfy() { cat "$WALKAWAY_HOME/logs/ntfy.log" 2>/dev/null | grep -c "job $1: $2 - "; }
ntfy_all() { cat "$WALKAWAY_HOME/logs/ntfy.log" 2>/dev/null | grep -c "	job $1: "; }
rest() { mkdir -p "$W/rest/$1"; if [[ -f "$3" ]]; then cp "$3" "$W/rest/$1/$2.json"; else printf '%s' "$3" > "$W/rest/$1/$2.json"; fi; }
# Every job not under test reports OK so it stays quiet.
quiet() {
  rest cc-optin-am run '[{"run_date":"x","session":"am","status":"DONE","halted_reason":null,"updated_at":"2026-11-13T16:25:19Z"}]'
  rest spc run '[{"run_date":"x","status":"ACCEPTED","listed":1,"accepted":1,"failed":0,"remaining":0,"updated_at":"2026-11-13T16:29:20Z"}]'
  rest extension-reports state "$FX/ext-state-1113.json"
  rest showingtime show '[{"obs_date":"x","showings":1,"first_seen_at":"2026-11-13T11:45:43Z"}]'
  rest bf-daily runs "$FX/bf-1113-recovered.json"
}

echo "S1 BF daily 11/13 replay (real rows): RETRYING silent, FAILED once after noon, OK resolves once"
fresh s1
tick "2026-11-13 06:10"
check "06:10 before the 06:30 window: PENDING, no check" [ "$(st bf-daily state)/$(st bf-daily last_action)" == "PENDING/window opens 06:30" ]
rest bf-daily runs "$FX/bf-1113-failures.json"
tick "2026-11-13 07:45"
check "07:45 three failed attempts: RETRYING" [ "$(st bf-daily state)" == "RETRYING" ]
check "RETRYING sent no ntfy" [ "$(ntfy_all bf-daily)" -eq 0 ]
tick "2026-11-13 11:59"
check "11:59 still inside the retry window: RETRYING" [ "$(st bf-daily state)" == "RETRYING" ]
tick "2026-11-13 12:01"
check "12:01 window passed: FAILED (the stub operator may already have moved it to FIXING)" bash -c "[[ '$(st bf-daily state)' == FAILED || '$(st bf-daily state)' == FIXING ]]"
check "exactly one FAILED ntfy naming the window" bash -c "[[ \$(grep -c 'job bf-daily: FAILED - not OK by 12:00: 3 failed attempt(s)' '$WALKAWAY_HOME/logs/ntfy.log') -eq 1 ]]"
check "job operator spawned once: diagnose bf-daily 2026-11-13" bash -c "[[ \$(grep diagnose '$WALKAWAY_HOME/op-calls.log') == 'diagnose bf-daily 2026-11-13' ]]"
tick "2026-11-13 12:03"
check "FAILED -> FIXING (stub operator), no second FAILED, no second diagnose" [ "$(st bf-daily state)/$(ntfy bf-daily FAILED)/$(grep -c diagnose "$WALKAWAY_HOME/op-calls.log")" == "FIXING/1/1" ]
check "FIXING follows the fix each tick (progress)" grep -q '^progress bf-daily 2026-11-13' "$WALKAWAY_HOME/op-calls.log"
rest bf-daily runs "$FX/bf-1113-recovered.json"
tick "2026-11-13 12:10"
check "recovered row: OK" [ "$(st bf-daily state)" == "OK" ]
check "exactly one resolved ntfy" bash -c "[[ \$(grep -c 'job bf-daily: OK - resolved: 2026-11-13T14:21:05Z BF lists daily 11/13: OK' '$WALKAWAY_HOME/logs/ntfy.log') -eq 1 ]]"
check "bf-daily total ntfy = 3 (FAILED, FIXING, resolved)" [ "$(ntfy_all bf-daily)" -eq 3 ]
tick "2026-11-14 06:00"
check "next day: PENDING, nothing carried (resolved)" [ "$(st bf-daily state)/$(st bf-daily date)/$(st bf-daily unresolved_from)" == "PENDING/2026-11-14/" ]

echo "S2 CC opt-in AM HALTED (real 11/04 row): terminal -> FAILED immediately; next day's OK reports the resolution"
fresh s2
rest cc-optin-am run "$FX/cc-am-1104-halted.json"
tick "2026-11-04 10:00"
check "10:00 HALTED: FAILED before the 15:45 window end (or already FIXING)" bash -c "[[ '$(st cc-optin-am state)' == FAILED || '$(st cc-optin-am state)' == FIXING ]]"
check "one FAILED ntfy with the halted reason" bash -c "[[ \$(grep -c 'job cc-optin-am: FAILED - HALTED: unrecognized submit response (batch 0); diagnosing' '$WALKAWAY_HOME/logs/ntfy.log') -eq 1 ]]"
rest cc-optin-am run '[{"run_date":"2026-11-05","session":"am","status":"DONE","halted_reason":null,"updated_at":"2026-11-05T18:26:02Z"}]'
tick "2026-11-05 08:00"
check "next day carries the unresolved failure" [ "$(st cc-optin-am state)/$(st cc-optin-am unresolved_from)" == "PENDING/2026-11-04" ]
tick "2026-11-05 13:30"
check "13:30 DONE (11/05 real time): OK" [ "$(st cc-optin-am state)" == "OK" ]
check "resolution ntfy names the failed day" grep -q 'job cc-optin-am: OK - resolved (failed 2026-11-04): DONE 2026-11-05T18:26:02Z' "$WALKAWAY_HOME/logs/ntfy.log"
check "cc-optin-am total ntfy = 3 (FAILED, FIXING, resolved)" [ "$(ntfy_all cc-optin-am)" -eq 3 ]

echo "S3 extension reports (rolling): 11/13 tracking_offsite error recovered on retry = silent; persisting > 2 h = FAILED once"
fresh s3
jq '(.[] | select(.report_type == "tracking_offsite")) |= (.last_error_at = "2026-11-13T13:05:00+00:00" | .last_success_at = "2026-11-12T20:00:00+00:00" | .last_error_message = "offsite pull failed: listReports timeout")' \
  "$FX/ext-state-1113.json" > "$W/ext-err.json"
rest extension-reports state "$W/ext-err.json"
tick "2026-11-13 08:05"
check "08:05 error: RETRYING" [ "$(st extension-reports state)" == "RETRYING" ]
rest extension-reports state "$FX/ext-state-1113.json"
tick "2026-11-13 08:20"
check "08:20 recovered on retry: OK, zero ntfy" [ "$(st extension-reports state)/$(ntfy_all extension-reports)" == "OK/0" ]
rest extension-reports state "$W/ext-err.json"
tick "2026-11-13 08:30"
tick "2026-11-13 10:29"
check "10:29 (1h59m in error): RETRYING, silent" [ "$(st extension-reports state)/$(ntfy_all extension-reports)" == "RETRYING/0" ]
tick "2026-11-13 10:31"
check "10:31 (> 2 h): FAILED once" [ "$(ntfy extension-reports FAILED)" -eq 1 ]
check "FAILED names the type and duration" grep -q 'job extension-reports: FAILED - in error: tracking_offsite (error 2026-11-13T13:05:00Z: offsite pull failed: listReports timeout) (persisting 121m); diagnosing' "$WALKAWAY_HOME/logs/ntfy.log"
jq '(.[] | select(.report_type == "bounty")) |= (.last_success_at = "2026-11-12T08:00:00+00:00")' "$FX/ext-state-1113.json" > "$W/ext-stale.json"
fresh s3b
rest extension-reports state "$W/ext-stale.json"
tick "2026-11-13 11:00"
check "no success in 26 h: FAILED at once" grep -q 'job extension-reports: FAILED - no success in 26 h: bounty; diagnosing' "$WALKAWAY_HOME/logs/ntfy.log"

echo "S4 check source errors: no false FAILED; WALKAWAY_JOB_ERROR_TICKS in a row -> ESCALATED once"
fresh s4
rest showingtime show '{"__error":"HTTP 503 upstream"}'
for m in 00 02 04 06; do WALKAWAY_JOB_ERROR_TICKS=3 WALKAWAY_JOBS_NOW=$(at "2026-11-13 08:$m") bash "$ROOT/lib/jobs.sh" tick >> "$W/tick.log" 2>&1; done
check "errors never read as FAILED" [ "$(ntfy showingtime FAILED)" -eq 0 ]
check "3rd consecutive error escalates once (priority high)" bash -c "[[ \$(grep -c \$'\\thigh\\tjob showingtime: ESCALATED - The showingtime check has failed 3 times in a row' '$WALKAWAY_HOME/logs/ntfy.log') -eq 1 ]]"

echo "S5 RealTea (Mon only): off-day untouched; Monday not generated by 09:15 -> FAILED"
fresh s5
tick "2026-11-13 09:30"
check "Friday: realtea-generate not scheduled" bash -c "[[ \$(jq -r .last_action '$WALKAWAY_HOME/jobs/state/realtea-generate.json') == 'not scheduled today (mon)' ]]"
rest realtea-generate issue '[]'
rest realtea-generate runs '[{"status":"blocked","issue_no":72,"gate_blocked_reason":"showings rollup missing 2026-11-15","failure_reason":null,"started_at":"2026-11-16T10:30:00Z"}]'
tick "2026-11-16 09:00"
check "Mon 09:00 blocked inside the window: RETRYING" [ "$(st realtea-generate state)" == "RETRYING" ]
tick "2026-11-16 09:16"
check "Mon 09:16: FAILED once with the gate reason" bash -c "[[ \$(grep -c 'job realtea-generate: FAILED - not OK by 09:15: latest run blocked: showings rollup missing 2026-11-15' '$WALKAWAY_HOME/logs/ntfy.log') -eq 1 ]]"

echo "S6 heartbeat lines"
fresh s6
rest bf-daily runs "$FX/bf-1113-failures.json"
tick "2026-11-17 06:10"
hb=$(WALKAWAY_JOBS_NOW=$(at "2026-11-17 06:10") bash "$ROOT/lib/jobs.sh" heartbeat)
check "06:10: bf-daily PENDING before its window is not listed" bash -c "! grep -q 'job bf-daily' <<< '$hb'"
tick "2026-11-17 07:45"
hb=$(WALKAWAY_JOBS_NOW=$(at "2026-11-17 13:00") bash "$ROOT/lib/jobs.sh" heartbeat)
check "13:00: RETRYING bf-daily listed" grep -q '^job bf-daily: RETRYING - 3 failed attempt' <<< "$hb"
tick "2026-11-17 13:00"
hb=$(WALKAWAY_JOBS_NOW=$(at "2026-11-17 13:00") bash "$ROOT/lib/jobs.sh" heartbeat)
check "OK jobs not listed (spc OK at 13:00)" bash -c "! grep -q 'job spc' <<< '$hb'"

echo "S6b job operator exits without a decision -> ESCALATED once"
fresh s6b
printf '#!/usr/bin/env bash\nsource "%s/lib/jobs.sh"; jstate_update "$2" "del(.operator_pid)"\n' "$ROOT" > "$W/op-silent.sh"
rest bf-daily runs "$FX/bf-1113-failures.json"
WALKAWAY_JOB_OPERATOR="$W/op-silent.sh" WALKAWAY_JOBS_NOW=$(at "2026-11-13 12:01") bash "$ROOT/lib/jobs.sh" tick >> "$W/tick.log" 2>&1; sleep 0.5
WALKAWAY_JOB_OPERATOR="$W/op-silent.sh" WALKAWAY_JOBS_NOW=$(at "2026-11-13 12:03") bash "$ROOT/lib/jobs.sh" tick >> "$W/tick.log" 2>&1
check "silent operator -> ESCALATED once" [ "$(st bf-daily state)/$(ntfy bf-daily ESCALATED)" == "ESCALATED/1" ]

echo "S6c (Codex cycle 2) a diagnosis still running at midnight keeps its pid: the new day waits for it"
fresh s6c
sleep 60 > /dev/null 2>&1 &
opp=$!
bash -c "source '$ROOT/lib/jobs.sh'; jstate_update bf-daily '.date = \"2026-11-13\" | .state = \"FAILED\" | .since = 0 | .operator_pid = $opp | .operator_spawned = true'"
tick "2026-11-14 00:05"
check "rollover kept operator_pid; the tick waited for the running operator" [ "$(st bf-daily date)/$(st bf-daily operator_pid)/$(st bf-daily last_action)" == "2026-11-14/$opp/job operator running" ]
kill "$opp" 2>/dev/null; wait "$opp" 2>/dev/null
tick "2026-11-14 00:07"
check "operator gone: the day proceeds" [ "$(st bf-daily last_action)" == "window opens 06:30" ]

echo "S7 walkaway status JOBS table"
out=$(WALKAWAY_JOBS_NOW=$(at "2026-11-17 13:00") bash "$ROOT/walkaway.sh" status)
check "JOBS header + every job row" bash -c "grep -q '^JOBS (2026-11-17' <<< \"\$1\" && for j in bf-daily cc-optin-am cc-optin-pm spc extension-reports showingtime realtea-generate realtea-publish; do grep -q \"^\$j \" <<< \"\$1\" || exit 1; done" _ "$out"
check "disabled PM shown as disabled" grep -q '^cc-optin-pm  *disabled' <<< "$out"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
