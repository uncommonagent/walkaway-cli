#!/usr/bin/env bash
# Re-pull executor tests (lib/data.sh data_act): method choice by age/hours, Amazon guards (business hours, CC batch,
# pacing), grouped firing, verify -> CLOSED, failed tries, the 2-try cap and the hand-off to the data operator.
# Triggers are stubbed (tests/fixtures/data/trigger-stub.sh); counts are fixtures; no network.
# shellcheck disable=SC2034  # variables read inside check's eval strings
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok   $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

export WALKAWAY_NTFY_DISABLED=1 WALKAWAY_HEARTBEAT_HOURS=off
TEST_YAML="$ROOT/tests/fixtures/data/series-test.yaml"
STUB="$ROOT/tests/fixtures/data/trigger-stub.sh"

fresh() {
  S=$(mktemp -d); mkdir -p "$S/fx"
  export WALKAWAY_HOME="$S" WALKAWAY_DATA_FIXTURES="$S/fx" WALKAWAY_DATA_FILE="${1:-$TEST_YAML}" WALKAWAY_DATA_TRIGGER_CMD="$STUB"
  echo '[]' > "$S/guard.json"; export WALKAWAY_DATA_GUARD_FIXTURE="$S/guard.json" WALKAWAY_DATA_OPERATOR="$ROOT/tests/fixtures/data/operator-stub.sh"
  unset STUB_LAND STUB_RC
}
at() { export WALKAWAY_DATA_NOW; WALKAWAY_DATA_NOW=$(TZ=America/New_York date -j -f '%Y-%m-%d %H:%M' "$1" +%s); }
fill() {
  python3 - "$S/fx/$1.json" "$2" "$3" "$4" <<'PY'
import json, sys, datetime, os
p, a, b, c = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
d = json.load(open(p)) if os.path.exists(p) else {}
x = datetime.date.fromisoformat(a); e = datetime.date.fromisoformat(b)
while x <= e:
    d[x.isoformat()] = c; x += datetime.timedelta(days=1)
json.dump(d, open(p, "w"))
PY
}
ev() { bash "$ROOT/lib/data.sh" evaluate "$1" > /dev/null 2>&1; }
gst() { jq -r --arg p "$2" ".gaps[\$p].$3 // empty" "$S/data/state/$1.json" 2>/dev/null; }
ntfy_n() { local n; n=$(grep -c "data $1: $2" "$S/logs/ntfy.log" 2>/dev/null); echo "${n:-0}"; }
trig_n() { local n; n=$(grep -c "^$1 " "$S/triggers.log" 2>/dev/null); echo "${n:-0}"; }

echo "R1 grouped re-pull fires once (from..to), REPULLING is silent, rows land -> CLOSED with before/after"
fresh; at "2026-11-18 13:00"
fill scratch-daily 2026-11-01 2026-11-17 12; fill scratch-daily 2026-11-15 2026-11-16 0
export STUB_LAND=12; ev scratch-daily
check "one trigger for both gaps, 11-15..11-16" '[[ "$(trig_n scratch-daily)" == 1 ]] && grep -q "^scratch-daily command true 2026-11-15 2026-11-16$" "$S/triggers.log"'
check "gaps REPULLING with verify_at = +30 min" '[[ "$(gst scratch-daily 2026-11-15 state)" == REPULLING && "$(gst scratch-daily 2026-11-15 verify_at)" == "$((WALKAWAY_DATA_NOW + 1800))" ]]'
check "REPULLING sends no ntfy (only the OPEN line)" '[[ "$(wc -l < "$S/logs/ntfy.log" | tr -d " ")" == 1 ]]'
at "2026-11-18 13:02"; ev scratch-daily
check "rows landed -> CLOSED via the command" '[[ "$(gst scratch-daily 2026-11-15 state)" == CLOSED && "$(gst scratch-daily 2026-11-16 closed_via)" == "command: true" ]]'
check "one CLOSED ntfy: rows 0 -> 12" '[[ "$(ntfy_n scratch-daily CLOSED)" == 1 ]] && grep -q "CLOSED - 2026-11-15 rows 0 -> 12, 2026-11-16 rows 0 -> 12" "$S/logs/ntfy.log"'
check "no second trigger" '[[ "$(trig_n scratch-daily)" == 1 ]]'

echo "R2 re-pull never lands: verify fails twice -> handed to the operator (cap 2), no third trigger"
fresh; at "2026-11-18 13:00"
fill scratch-daily 2026-11-01 2026-11-17 12; fill scratch-daily 2026-11-16 2026-11-16 0
ev scratch-daily
at "2026-11-18 13:10"; ev scratch-daily
check "inside verify window: still REPULLING, no new trigger" '[[ "$(gst scratch-daily 2026-11-16 state)" == REPULLING && "$(trig_n scratch-daily)" == 1 ]]'
at "2026-11-18 13:31"; ev scratch-daily
check "verify failed -> try 2 fired" '[[ "$(gst scratch-daily 2026-11-16 failed_tries)" == 1 && "$(trig_n scratch-daily)" == 2 && "$(gst scratch-daily 2026-11-16 state)" == REPULLING ]]'
at "2026-11-18 14:02"; ev scratch-daily
check "second failure -> need_operator, reason names the method" '[[ "$(gst scratch-daily 2026-11-16 need_operator)" == true && "$(gst scratch-daily 2026-11-16 reason)" == "re-pull failed twice (command: true)" ]]'
at "2026-11-18 15:00"; ev scratch-daily
check "no third trigger after the cap" '[[ "$(trig_n scratch-daily)" == 2 ]]'

echo "R3 trigger failure (rc != 0) counts as a failed try"
fresh; at "2026-11-18 13:00"
fill scratch-daily 2026-11-01 2026-11-17 12; fill scratch-daily 2026-11-17 2026-11-17 0
export STUB_RC=1; ev scratch-daily
check "OPEN, failed_tries 1, last_try rc 1" '[[ "$(gst scratch-daily 2026-11-17 state)" == OPEN && "$(gst scratch-daily 2026-11-17 failed_tries)" == 1 && "$(gst scratch-daily 2026-11-17 last_try.rc)" == 1 ]]'
at "2026-11-18 13:02"; ev scratch-daily
check "second failed trigger -> 2 tries" '[[ "$(gst scratch-daily 2026-11-17 failed_tries)" == 2 && "$(trig_n scratch-daily)" == 2 ]]'
at "2026-11-18 13:04"; ev scratch-daily
check "-> need_operator" '[[ "$(gst scratch-daily 2026-11-17 need_operator)" == true ]]'

echo "R4 Amazon guard: business hours, CC batch in flight, pacing; a deferral is not a try"
fresh; at "2026-11-18 08:30"
fill scratch-amazon 2026-11-01 2026-11-17 9; fill scratch-amazon 2026-11-17 2026-11-17 0
at "2026-11-18 11:00"; WALKAWAY_DATA_NOW=$(( WALKAWAY_DATA_NOW )) ; at "2026-11-18 19:30"; ev scratch-amazon
check "19:30: outside 09:00-19:00 -> no trigger, waiting" '[[ "$(trig_n scratch-amazon)" == 0 && "$(gst scratch-amazon 2026-11-17 tries_today)" == 0 ]] && grep -q "outside Amazon business hours 09:00-19:00" <<< "$(jq -r .last_action "$S/data/state/scratch-amazon.json")"'
fresh; fill scratch-amazon 2026-11-01 2026-11-17 9; fill scratch-amazon 2026-11-17 2026-11-17 0
echo '[{"session":"am","status":"RUNNING"}]' > "$S/guard.json"
at "2026-11-18 11:30"; ev scratch-amazon
check "CC batch RUNNING -> no trigger, waiting on CC batch" '[[ "$(trig_n scratch-amazon)" == 0 ]] && grep -q "CC batch in flight" <<< "$(jq -r .last_action "$S/data/state/scratch-amazon.json")"'
echo '[{"session":"am","status":"DONE"}]' > "$S/guard.json"
at "2026-11-18 11:32"; ev scratch-amazon
check "batch DONE -> run-now fires (tracking_offsite, age 1)" '[[ "$(trig_n scratch-amazon)" == 1 ]] && grep -q "^scratch-amazon run_now tracking_offsite 2026-11-17 2026-11-17$" "$S/triggers.log"'
check "pace stamp written" '[[ "$(cat "$S/data/state/_amazon_last_trigger")" == "$WALKAWAY_DATA_NOW" ]]'
# a second Amazon series inside 15 min waits (real yaml entry: tracking_onsite run-now, same guard)
export WALKAWAY_DATA_FILE="$ROOT/data/series.yaml"; fill amz-tracking-onsite 2026-11-01 2026-11-17 2; fill amz-tracking-onsite 2026-11-17 2026-11-17 0
at "2026-11-18 11:40"; ev amz-tracking-onsite
check "amz-tracking-onsite 8 min later: paced, no trigger" '[[ "$(trig_n amz-tracking-onsite)" == 0 ]] && grep -q "paced: last Amazon trigger 8m ago" <<< "$(jq -r .last_action "$S/data/state/amz-tracking-onsite.json")"'
at "2026-11-18 11:48"; ev amz-tracking-onsite
check "16 min later: fires run-now tracking_onsite" '[[ "$(trig_n amz-tracking-onsite)" == 1 ]] && grep -q "^amz-tracking-onsite run_now tracking_onsite 2026-11-17" "$S/triggers.log"'

echo "R5 hours windows (real cc entry): run-now pulls D-2 only before noon; after noon age 2 has no path"
fresh "$ROOT/data/series.yaml"
fill amz-creator-connections 2026-11-01 2026-11-16 7; fill amz-creator-connections 2026-11-16 2026-11-16 0
at "2026-11-18 11:30"; ev amz-creator-connections
check "11:30: run-now cc fires for 11-16 (age 2)" '[[ "$(trig_n amz-creator-connections)" == 1 ]] && grep -q "^amz-creator-connections run_now cc 2026-11-16 2026-11-16$" "$S/triggers.log"'
fresh "$ROOT/data/series.yaml"
fill amz-creator-connections 2026-11-01 2026-11-16 7; fill amz-creator-connections 2026-11-16 2026-11-16 0
at "2026-11-18 12:30"; ev amz-creator-connections
check "12:30: no method for age 2 -> need_operator, no trigger" '[[ "$(trig_n amz-creator-connections)" == 0 && "$(gst amz-creator-connections 2026-11-16 need_operator)" == true && "$(gst amz-creator-connections 2026-11-16 reason)" == "no re-pull path for age 2" ]]'

echo "R6 self-heal: nothing fires, the wait is the try"
fresh; at "2026-11-18 13:00"
fill scratch-amazon 2026-11-01 2026-11-17 9; fill scratch-amazon 2026-11-15 2026-11-15 0
ev scratch-amazon
check "11-15 (age 3) REPULLING via self-heal, verify +180 min" '[[ "$(gst scratch-amazon 2026-11-15 state)" == REPULLING && "$(gst scratch-amazon 2026-11-15 last_try.label)" == "self-heal wait" && "$(gst scratch-amazon 2026-11-15 verify_at)" == "$((WALKAWAY_DATA_NOW + 10800))" ]]'
fill scratch-amazon 2026-11-15 2026-11-15 9
at "2026-11-18 15:00"; ev scratch-amazon
check "extension healed it -> CLOSED via self-heal wait" '[[ "$(gst scratch-amazon 2026-11-15 state)" == CLOSED && "$(gst scratch-amazon 2026-11-15 closed_via)" == "self-heal wait" ]]'

echo "R7 no path / lost data: age beyond every method, historical=no"
fresh; at "2026-11-18 13:00"
fill scratch-daily 2026-11-01 2026-11-17 12; fill scratch-daily 2026-11-08 2026-11-08 0
ev scratch-daily
check "age 10 (methods cover 1-3) -> need_operator, no trigger" '[[ "$(gst scratch-daily 2026-11-08 need_operator)" == true && "$(gst scratch-daily 2026-11-08 reason)" == "no re-pull path for age 10" && "$(trig_n scratch-daily)" == 0 ]]'
fresh; at "2026-11-18 14:00"
fill scratch-lost 2026-11-01 2026-11-18 4; fill scratch-lost 2026-11-16 2026-11-16 0
ev scratch-lost
check "historical=no -> reason says the source cannot re-pull" '[[ "$(gst scratch-lost 2026-11-16 reason)" == "no re-pull path for age 2 (source cannot re-pull a past period)" ]]'

echo "R8 requires_fix hook: unused before the fix merged, used after (dates substituted)"
fresh; at "2026-11-18 13:00"
fill scratch-amazon 2026-11-01 2026-11-17 9; fill scratch-amazon 2026-11-08 2026-11-09 0
ev scratch-amazon
check "before the fix: no path (ages 9-10)" '[[ "$(gst scratch-amazon 2026-11-08 need_operator)" == true && "$(trig_n scratch-amazon)" == 0 ]]'
jq '.hook_merged = true | .gaps |= map_values(del(.need_operator) | .failed_tries = 0)' "$S/data/state/scratch-amazon.json" > "$S/t" && mv "$S/t" "$S/data/state/scratch-amazon.json"
at "2026-11-18 13:02"; ev scratch-amazon
check "after the fix merged: the hook fires once for 11-08..11-09" '[[ "$(trig_n scratch-amazon)" == 1 ]] && grep -q "^scratch-amazon command echo fix-hook {from} {to} 2026-11-08 2026-11-09$" "$S/triggers.log"'

echo "R9 run-now allow-list (direct, no network)"
fresh
# shellcheck source=lib/data.sh
out=$(WALKAWAY_DATA_FILE="$ROOT/data/series.yaml" bash -c "source '$ROOT/lib/data.sh'; cfg=\$(data_config); _run_now \"\$cfg\" \"\$(data_get \"\$cfg\" amz-tracking-offsite)\" cc_optin_runs; echo rc=\$?")
check "a non-allow-listed report type is refused before any request" '[[ "$out" == *"rc=2"* ]] && grep -q "run_now refused: cc_optin_runs not allow-listed" "$S/logs/data-repull.log"'

echo "R10 a post_fix gap tries the fix hook before the older path (which already failed it)"
fresh; at "2026-11-18 13:00"
fill scratch-amazon 2026-11-01 2026-11-17 9; fill scratch-amazon 2026-11-16 2026-11-16 0
mkdir -p "$S/data/state"
jq -n '{series: "scratch-amazon", ok_periods: [], hook_merged: true, fix_merged: true,
        gaps: {"2026-11-16": {state: "OPEN", status: "missing", rows_before: 0, rows_now: 0, failed_tries: 0, tries_today: 0, post_fix: true}}}' > "$S/data/state/scratch-amazon.json"
ev scratch-amazon
check "age 2 (self-heal covers it) but post_fix -> the fix hook fires" '[[ "$(trig_n scratch-amazon)" == 1 ]] && grep -q "^scratch-amazon command echo fix-hook {from} {to} 2026-11-16 2026-11-16$" "$S/triggers.log"'

echo "R11 http trigger (Phase 6 live finding): a route that never answers in time = delivered; no connection = failed try"
fresh
printf 'Z=test-cron-secret\n' > "$S/env"
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
python3 - "$PORT" > /dev/null 2>&1 <<'PY' &
import http.server, sys, time
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        time.sleep(5)   # a cold start / long sync: answers after the client timeout
        self.send_response(200); self.end_headers(); self.wfile.write(b"{}")
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
SRV=$!
sleep 1
CFG=$(jq -cn --arg env "$S/env" --arg url "http://127.0.0.1:$PORT" '{sources: {scratch: {env_file: $env, url_var: "X", key_var: "Y", app_url: $url, cron_secret_var: "Z"}}}')
SER='{"name":"scratch-http","source":"scratch"}'
slow=$(WALKAWAY_DATA_HTTP_TIMEOUT=2 bash -c "source '$ROOT/lib/data.sh'; _http_get '$CFG' '$SER' /api/cron/x; echo rc=\$?")
kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null
refused=$(WALKAWAY_DATA_HTTP_TIMEOUT=2 bash -c "source '$ROOT/lib/data.sh'; _http_get '$CFG' '$SER' /api/cron/x; echo rc=\$?")
check "slow route past the client timeout (curl exit 28) -> rc 0 (delivered; verify decides)" '[[ "$slow" == *"rc=0"* ]] && grep -q "(curl exit 28)" "$S/logs/data-repull.log"'
check "connection refused (HTTP 000, curl exit 7) -> rc 1 (a failed try, not a fired re-pull)" '[[ "$refused" == *"rc=1"* ]] && grep -q "(curl exit 7)" "$S/logs/data-repull.log"'

echo "R12 a re-pull never fires a send: the ST URL trigger waits until today's Pulse brief row exists (real bb entry)"
fresh "$ROOT/data/series.yaml"
fill bb-showings-daily 2026-11-01 2026-11-16 21; fill bb-showings-daily 2026-11-17 2026-11-17 0
echo '[]' > "$S/guard.st_brief_sent.json"
at "2026-11-18 13:05"; ev bb-showings-daily
check "brief not sent yet -> no trigger, waiting with the reason" '[[ "$(trig_n bb-showings-daily)" == 0 ]] && grep -q "Pulse brief not sent yet" <<< "$(jq -r .last_action "$S/data/state/bb-showings-daily.json")" && [[ "$(gst bb-showings-daily 2026-11-17 tries_today)" == 0 ]]'
echo '[{"send_date":"2026-11-18"}]' > "$S/guard.st_brief_sent.json"
at "2026-11-18 13:07"; ev bb-showings-daily
check "brief sent -> the ST URL trigger fires for 11-17 (age 1)" '[[ "$(trig_n bb-showings-daily)" == 1 ]] && grep -q "^bb-showings-daily command open -g -a \"Google Chrome\" \"https://throughlinepro.com/#tl-ext-run-daily\" 2026-11-17 2026-11-17$" "$S/triggers.log"'

echo ""
echo "Results: $PASS passed, $FAIL failed"
(( FAIL == 0 ))
