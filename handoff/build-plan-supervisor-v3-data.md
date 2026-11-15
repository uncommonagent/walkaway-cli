# Walkaway Build Plan: supervisor-v3-data

## RESUME DIRECTIVE (auto, resume 1/2, 2026-11-15 14:28 ET) - read first
The previous builder session ended without a build or failure report (STALLED: no activity 40m). Continue from handoff/build-log-supervisor-v3-data.md and the newest phase report: do NOT redo committed phases; finish the first unfinished phase, then continue the plan. Any earlier RESUME DIRECTIVE not marked [DONE] still applies.
No-op resume: if every phase is already committed and handoff/build-report-supervisor-v3-data.md exists, re-run nothing. Append one line "build-report supervisor-v3-data (no-op resume 1/2, <ET timestamp>): all phases already complete" to handoff/build-report-supervisor-v3-data.md (and build-report-CURRENT.md), commit and push it, then exit.

## RESUME DIRECTIVE (auto, approved fix 1, 2026-11-15 12:51 ET) - read first
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

## Feature name
`supervisor-v3-data`

## Branch name
`feature/supervisor-v3-data`

## Goal
No data loss from any scheduled extension pull or ingest cron in Showrunner or Throughline. The supervisor watches
every dated data series (not just "did the job run today"), detects missing or short days, re-pulls them through the
job's own pull path, verifies the rows landed, and launches a fix build when a re-pull cannot succeed. Jim hears one
ntfy line per gap found and one per gap closed.

## Evidence (Claude, 11/15)
- jobs.yaml (v2) covers: bf-daily, cc-optin-am/pm, spc, extension-reports (aggregate "succeeded within 26 h"),
  showingtime, realtea-generate/publish. It checks today's run, not historical gaps, and has no re-pull/backfill.
- Not covered:
  - Throughline extension tools/showings-daily-pull: ST daily pull (+ retry + failed-dates retry alarms), BrokerBay
    (bb-core.js), TMA (tma-core.js), recap (recap-core.js), ST single-listing refresh poll.
  - Throughline Vercel crons (vercel.json): pulse-daily-sync (+ ifMissing), pulse-signals, pulse-market-health,
    pulse-revision-sweep, pulse-macro, pulse-events(+refresh), pulse-member-snapshot, daily-pulse-brief,
    showingtime-maintenance, recap-offer-sync, offer-inbox-scan, gmail-poll, curb-inquiry-scan,
    field-guide-dispatch.
  - Showrunner extension report types individually: tracking_offsite, tracking_offsite_today, tracking_onsite, cc
    (morning/evening), spc (morning/evening), connect_summary (morning/evening), bounty, linked_product orders.
- 11/14: tracking_offsite failed 07:07 and recovered on retry; a day that never recovers today leaves a silent hole.

## Decisions
Jim 11/15: monitor every Showrunner + Throughline daily extension run; Claude launches fixes and re-pulls so there is
no data loss. Protected actions unchanged (CC/SPC opt-ins, Substack publish, list publishes, spend, credentials,
deletes) - those still escalate; a RE-PULL of data is never protected.

## Quality rules
Protocol merge-gate standard; every series check is proven against real rows.

## Source of truth
Each series' own table (both Supabase projects): e.g. amazon_tracking_daily, amazon_creator_connections_daily,
amazon_sponsored_products_daily, amazon_connect_summary_daily, amazon_bounties_daily, idea_list_asin_stats,
pulse_showings_daily, BrokerBay/TMA/recap tables (Phase 0 finds them), pulse_* tables, extension_report_state,
st session-state table; Vercel cron logs for cron jobs.

## What to build
0. Phase 0 inventory (read-only): every scheduled pull/cron in both repos -> data/series.yaml entries: name, owner
   repo, schedule, the table + date column it writes, expected cadence (daily / weekday / weekly), expected row
   floor (from the last 30 days' median, e.g. ST total showings row = 1/day; tracking_offsite rows >= 50% of 30-day
   median), lag (data for D lands on D+1), re-pull method (extension run-now with date range, cron URL with date
   param, Inngest event), and whether the source allows historical re-pulls (Amazon reports: yes by date; ST: yes by
   date; BrokerBay/TMA: Phase 0 states). Archive one real passing check per series.
1. Gap detector (every supervisor tick, 14-day lookback): for each series, dates with missing rows or rows under
   the floor, past their own retry window -> GAP. States per gap: OPEN, REPULLING, CLOSED, FIXING, ESCALATED.
2. Re-pull: trigger the series' own re-pull for exactly the gap dates (paced, business hours for Amazon, never
   during a CC batch, max 2 tries per gap per day), then verify rows landed at/above the floor -> CLOSED.
   Uses only existing pull paths; adds date-range run-now hooks where a job lacks one (owner repo change, via a fix
   build).
3. If re-pull fails twice or no re-pull path exists: operator writes job-incident file and a template-v2 fix plan in
   the owner repo (one builder per repo, queue if busy). After merge, re-pull every open gap date for that series and
   confirm CLOSED.
4. ntfy: one line on gap OPEN (series, dates), one on CLOSED (rows landed), one on ESCALATED with one question.
   09/13/17 heartbeat lists open gaps only.
5. `walkaway status` gets a DATA table: series, last complete date, open gaps, last action.

## Do NOT build
No changes to how pulls work except adding date-range run-now hooks via fix builds. No dashboards. No protected
actions.

## Acceptance criteria
- [ ] AC1 series.yaml covers every scheduled pull/cron found in Phase 0 (inventory list vs yaml diff = 0), each with
      a real passing check dumped.
- [ ] AC2 Tests: gap detection (missing, short, lag-aware, weekday cadence), retry window respected, re-pull cap,
      escalation on no re-pull path.
- [ ] AC3 Drill on a scratch series: delete-free simulation (fixture rows) -> OPEN -> re-pull stub -> CLOSED; failing
      re-pull -> fix plan queued; exactly one ntfy per transition (drill topic).
- [ ] AC4 Live: run the detector over the real last 14 days, archive the gap report; any real gaps found are
      re-pulled and closed (or escalated with reason). Evidence per gap: rows before/after.
- [ ] AC5 Supervisor reloaded; `walkaway status` shows JOBS + DATA tables (archived). shellcheck 0, tests green.

## Gate checklist
Diff inventory vs series.yaml; open the 14-day gap report and the before/after rows for each closed gap; count drill
ntfy lines per transition.

## Stop rules
Never delete or overwrite existing rows to "test". Never trigger CC/SPC opt-ins or any publish. Amazon re-pulls only
in business hours and never while a CC batch is in flight.

## Escalate to Jim
Any re-pull that would need credentials, spend, or a protected action; any series whose source cannot re-pull a past
date (state which dates are lost).
