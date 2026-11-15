# Phase 3 report - supervisor-v3-data (re-pull executor)

- **data_act** (`lib/data.sh`) runs every tick after detection:
  1. Verifies due tries: a REPULLING gap past verify_at whose rows did not reach the floor is a failed try (back to OPEN, silent).
  2. Picks a method for each OPEN gap: the first repull entry covering the gap's age, the local hour (cc/spc run-now: D-2 before noon, D-1 after) and, for `requires_fix` hooks, a merged fix.
  3. Fires each chosen method ONCE for all of its gaps (from = oldest, to = newest).
  4. Hands the rest to the data operator (`need_operator` + reason).
- **Trigger methods** (existing pull paths only):
  - `run_now`: one PATCH of `extension_report_state.run_now_requested_at` for one report type from an allow-list (tracking_offsite, tracking_onsite, bounty, cc, spc, connect_summary), scoped to Audrey's user id. This is what the Showrunner run-now route writes. Any other type is refused before a request goes out.
  - `http`: GET <app_url><path>. The Bearer CRON_SECRET is read at call time and goes to curl on stdin.
  - `command`: the series' fixed command, with ISO {from}/{to}.
  - `self_heal`: nothing fires; the wait is the try.
  - Every trigger is logged to `$WALKAWAY_HOME/logs/data-repull.log`, including the rows before.
- **Guards:**
  - Amazon: business hours 09:00-19:00 (Showrunner BUSINESS_HOURS); no CC batch in flight (read-only GET of today's cc_optin_runs + batches); one Amazon trigger per 15 min across all series.
  - A deferral is not a try.
  - Max 2 tries per gap per local day. Two failed tries (or a failed trigger rc) means `need_operator`; no third trigger.
- **No path:** a gap whose age no method covers goes straight to the operator. The reason states when the source cannot re-pull a past period (historical "no").
- **YAML 1.1 fix:** `historical: no` parsed as boolean false, so the values are now quoted strings. Caught by R7.
- **tests/test-data-repull.sh (new, 28/28):**
  - R1 grouped fire, silent REPULLING, CLOSED with before/after.
  - R2 verify fails twice -> operator, no third try. R3 trigger rc counts as a try.
  - R4 business hours / CC batch / pacing across two series. R5 the real cc hours window.
  - R6 self-heal. R7 no path / lost data. R8 fix hook only after the merge. R9 the run-now allow-list.
  - `tests/fixtures/data/trigger-stub.sh` can "land" rows.
- test-data-gaps: two detection asserts now accept OPEN or REPULLING, because evaluate acts right after detect. Still 32/32.
- Gates: shellcheck 0; 240/240 (data-gaps 32, data-repull 28, parse 7, states 18, v2-AC1 12, jobs-states 38, job-operator 37, operator 68).
- No live trigger has fired: nothing calls data.sh from the supervisor yet, and every test uses the stub.
