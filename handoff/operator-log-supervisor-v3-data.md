# Operator log - supervisor-v3-data

Every supervisor/operator decision for this build, newest last.

## 2026-11-15 12:51 ET - TRIAGE: APPROVE (1/3)
Report: /Users/jimross/Projects/walkaway-cli/handoff/failure-report-supervisor-v3-data-codex.md
Rationale: Both Codex findings are real defects in what the plan asks for. The P1 means the post-fix re-pull (item 3: "after merge, re-pull every open gap date") can't run. The P2 lets a Supabase outage use up re-pull tries (item 2's 2-try cap) and hand the gap to the operator for no reason. The proposed fixes only change the supervisor's own series.yaml and lib/data.sh, plus tests. The new requires_fix methods only fire after a fix build adds the date-range hook, which is the exact exception the plan's Do NOT build list allows. The plan says a data re-pull is never protected. The existing Amazon business-hours/CC-batch guards and the st_brief_sent guard stay in place, and no live meta-sync/pulse-signals/pulse-market-health calls or row writes are needed. So I'm approving as proposed, plus a gating test and the stop rule for Codex cycle 2.
Directive written to the plan:
RESUME DIRECTIVE (operator, Codex cycle 1 P1 + P2), approved as proposed in failure-report-supervisor-v3-data-codex.md, with these additions.

What failed: Codex cycle 1 at 275c4b9 found two real problems.
- P1: fix_hook contracts have no executable requires_fix re-pull method, and http paths don't get {from}/{to}.
- P2: a verify uses up a try even when this tick's count errored.

Fix to apply:
1. data/series.yaml: every watched series with historical != "no" gets a fix_hook contract AND a matching {method, requires_fix: true, ages: all} entry. Both use {from}/{to}, exactly as listed in the failure report:
   - amz-connect-summary (amazon guard)
   - markable-spend (no amazon guard)
   - meta-daily-metrics, http /api/cron/meta-sync?from={from}&to={to}
   - pulse-daily-snapshots and pulse-weekly-stats, both http /api/cron/pulse-daily-sync?from={from}&to={to}
   - pulse-signal-scores and pulse-market-health: from/to paths, NOT ?scope=full
   - tma-cohort-showings (#tl-ext-repull=tma)
   - recap-reports (#tl-ext-repull=recap)
   - pulse-showings-weekly (ST hook, st_brief_sent guard)
   Lost-data series (historical "no") keep no hook. Their gaps escalate as lost dates.
2. lib/data.sh _fire: substitute {from}/{to} in http paths and check them against the ISO date regex, the same as for commands. In data_act, `to` = the END of the newest gap period: anchor+6 for weekly, the last day of the month for monthly, the day itself for daily.
3. lib/data.sh P2:
   - data_detect sets .gaps[p].counted_at=now on every successful count of that period.
   - data_act step 1 fails a try only when counted_at >= verify_at. Otherwise it waits for the next good count.
4. Regression tests. Each must FAIL on 275c4b9 and PASS after the fix. Archive both outputs under handoff/.
   - (a) series.yaml contract test, as described in the report.
   - (b) pulse-weekly-stats week gap with hook_merged true: from=Monday, to=Sunday.
   - (c) meta-daily-metrics with a stub trigger: the http path gets the substituted dates.
   - (d) P2: a count error at verify_at leaves failed_tries 0, the state REPULLING, and no new trigger. The next good count below the floor fails exactly one try.
   - ADDITION (e): a requires_fix method NEVER fires while hook_merged is false. The series falls through to the operator or escalates as today, so none of the new methods can hit a live endpoint before its fix build merges.

Constraints (unchanged):
- Write every lib/ edit atomically (tmp file + mv), because the live supervisor runs this tree every 120 s.
- Tests that use the real series.yaml stub the data operator (tests/fixtures/data/operator-stub.sh).
- Never call meta-sync, pulse-signals, pulse-market-health or any new hook live to test.
- Never write, overwrite or delete rows.

Re-run:
- shellcheck -S warning on all scripts (expect 0).
- All tests/test-*.sh green (record the new counts).
- tests/drill/run-data-drill.sh stays 18/18.
- Codex cycle 2 (FINAL), appended to handoff/codex-review-supervisor-v3-data.md. If cycle 2 returns a P1, STOP and write a failure report. Do not start a cycle 3.

Then finish Phase 6:
- Archive the BB 11-14 re-pull with rows before/after from data-repull.log, data/state/bb-showings-daily.json and supervisor.log.
- Archive the final `walkaway status` (JOBS + DATA).
- Write handoff/phase-6-report-supervisor-v3-data.md.

Then Phase 7: evidence MANIFEST, PR, CI green, build report LAST.

Then continue the plan from the build log; do not redo committed phases.

## 2026-11-15 14:28 ET - RESUME (auto 1/2)
Trigger: STALLED: no activity 40m. Killed leftovers, wrote RESUME DIRECTIVE (auto) to the plan, relaunching.
