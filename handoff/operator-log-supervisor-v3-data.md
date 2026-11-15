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

## 2026-11-15 14:41 ET - MERGE GATE: PASS (PR #3)
Verdict: PASS (screenshots opened: 0, JSON parsed: 3, rows spot-checked: 68, CI green: true, Codex closed: true)
Criteria:
- AC1: MET - phase0-inventory.txt lists 49 ids. data/series.yaml has 21 entries with watch:true (lines 80-457) and 28 watch:false entries, each with a reason (lines 472-504). The names match the inventory one to one, so the diff is 0, matching ac1-inventory-diff-final.txt 'rc=0 ids=49 yaml=49 watched=21'. ac1-series-check-dump-final.md (13:48) has all 21 sections PASS, each with exact counts and the printed REST query. The plan's 'linked_product orders' is explained in phase0-inventory.md:82: no scheduled pull exists.
- AC2: MET - ac5-gates-report-time.txt (14:30, HEAD 3649525): data-gaps 38/38, data-repull 92/92, data-operator 25/25, 335/335 total, shellcheck rc=0. MANIFEST maps missing, short, lag/ready_by, weekday/weekly cadence, retry window, 2-try cap and no-path escalation to these suites. Regressions R11-R19 each have archived fail-before/pass-after runs. git diff 3649525..HEAD touches only handoff/ and ROADMAP.md, so the gate run covers the HEAD code. Existing test files are unchanged vs main.
- AC3: MET - ac3-drill/drill-transcript.txt: 18 passed, 0 failed (13:15, topic jim-walkaway-data-drill-603a25b7). drill-repull went OPEN->CLOSED, rows 0->12. drill-nopath failed 2 tries, got a FIXING template-v2 plan queued behind drill-busy, then CLOSED via the hook for exactly 2026-11-12 after the simulated merge. drill-lost went OPEN->ESCALATED at priority 4. ntfy-poll.json parses to 8 messages, and they match ntfy-local.log (8) line for line. There is exactly one ntfy per transition and no REPULLING ping.
- AC4: MET - ac4-live/gap-report-14d-before-enable.md: 20 series are complete, and bb-showings-daily is missing 11-09..11-13. The 11-14 live re-pull fired twice (13:01:34 and 13:47:31, supervisor-data-lines-final.log). Both verifies found 0 rows, and the gap went ESCALATED at 14:34:33. The reason is a BrokerBay sign-in, which is a credential and therefore protected, so escalation is the plan's required route. bb-check-1436.json shows 11-09..11-14 count 0 and 11-08..11-05 count 21. state-bb-showings-daily-final.json has all 6 gaps ESCALATED, with 11-14 failed_tries 2. bb-1114-repull.md has a rows before/after table for every gap.
- AC5: MET - ac4-live/enable-and-reload.txt: data.enabled, launchd bootout+bootstrap at 12:35:07, state running, interval 120 s. ac4-live/walkaway-status-final.txt (14:35:41) shows the builds table, JOBS (8 jobs) and DATA (21 series, bb-showings-daily ESCALATED 11-09..11-14). shellcheck rc 0 and 335/335 in ac5-gates-report-time.txt. The lib/supervisor.sh diff is +12/-1: the data tick and heartbeat, both gated on data.enabled.
Findings:
- Info, not blocking: the repo has no CI (0 workflows, and the supervisor sees statusCheckRollup []). PR #3 is OPEN and CLEAN. ci_green=true under the same empty-rollup grace rule as the PR #1 and #2 gates.
- Info, not blocking: Codex is closed. Cycle 1 (275c4b9) found 1 P1 and 1 P2, both fixed after operator approval (49377b5, R13-R17 fail-before/pass-after). Cycle 2, the final one (49377b5), found 0 P1 and 2 P2, both fixed (R18/R19 88/92 -> 92/92). The 2-cycle cap was respected.
- Verification limit: I could not re-run shellcheck or the test suites in this session (permission prompts). I relied on ac5-gates-report-time.txt (14:30, HEAD 3649525) after confirming git diff 3649525..HEAD changes only handoff/ and ROADMAP.md. I also could not run gh/git against the remote to confirm the PR head SHA equals local HEAD b4e7d95, so I used the supervisor-observed CLEAN state.
- Spot check, 68 rows: I compared the row counts in ac1-series-check-dump-final.md (13:48) with the independent 12:22 dump (ac1-series-check-dump.md) for amz-tracking-offsite/onsite, creator-connections, sponsored-products, connect-summary, markable-spend, meta-daily-metrics and st-showings-daily, 11-08..11-14. Every compared row matches. I also traced bb-showings-daily 11-05..11-14 from bb-check-1436.json to the dump, the state file and the bb-1114-repull.md table. I did not re-query Supabase live, because that needs the service-role key (protected).
- Info, not blocking: the BrokerBay gap 11-09..11-14 stays ESCALATED and waits on Jim's sign-in. The dates are not lost (90-day re-pull), and the backfill needs the #tl-ext-repull=bb fix build after the sign-in.
- Info, not blocking: there is no CLI path yet to answer a data ESCALATED (walkaway answer), and Jim got two ESCALATED pings for one root cause. Both are deferred in the build report and ROADMAP.
- Info, not blocking: 0 screenshots, because this build has no UI.
