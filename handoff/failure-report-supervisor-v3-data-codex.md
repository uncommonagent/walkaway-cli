# Failure report - supervisor-v3-data - Codex cycle 1 (P1 stop)

Phase 7 (Codex review, cycle 1 of 2) at HEAD 275c4b9 returned 1 P1 and 1 P2. Both are real
(handoff/codex-review-supervisor-v3-data.md). Per WALKAWAY_BUILD_PROTOCOL.md a P1 is a stop rule, so the build stopped
here. Nothing is broken live: data watching is ON and has been since 12:35 ET.
- The only live gap so far is bb-showings-daily 11-09..11-13. It was ESCALATED 12:36 with one question (BrokerBay
  session). The P1 cannot fire until a fix build merges.
- The P2 needs a Supabase outage at the same moment as a verify.
- Proposed fixes 1-2 are in scope: they make the plan's items 2 and 3 work as written. Neither touches a PROTECTED
  action.

## Where the build is
- Phases 0-6 are committed (see build-log-supervisor-v3-data.md).
  - Phase 6 smoke: AC1 final dump 21/21 PASS, inventory diff 0. AC3 live drill 18/18 (real claude; ntfy 8 polled ==
    8 sent). Http re-pull path probed live (200 skipped). Phase 6 fixes R11/R12 shipped with fail-before/pass-after
    evidence.
  - AC4: data watching enabled 12:35:05 ET and supervisor reloaded 12:35:07. The first tick (12:35:16) checked all
    21 series: 20 have no gaps; bb-showings-daily OPEN 11-09..11-13, then the operator ESCALATED it 12:36:09.
- **Phase 6 is not finished.** These still need to be archived (handoff/phase-6-report-supervisor-v3-data.md lists
  them):
  - the BB 11-14 re-pull through the ST URL trigger: it becomes ready 13:00 ET, so the 13:00+ ticks fire it; evidence
    is in data-repull.log, data/state/bb-showings-daily.json and supervisor.log;
  - the final AC4/AC5 status archive.

## P1 - executable hooks for every fix contract (REAL)
`data/series.yaml` advertises a `fix_hook` on seven series with no `requires_fix` repull method: amz-connect-summary,
markable-spend, meta-daily-metrics, pulse-daily-snapshots, pulse-weekly-stats, tma-cohort-showings, recap-reports.
After such a fix merges, `_method_for` returns `none`, and data-operator rule 2 escalates instead of re-pulling.

`_fire` substitutes `{from}`/`{to}` only in commands. Http paths are not substituted. Weekly and monthly gaps would
pass period anchors, not the period's full date range.

### Proposed fix
1. **data/series.yaml**: every watched series whose source can re-pull (`historical` yes / partial / unknown) gets a
   `fix_hook` contract AND a matching `{method, requires_fix: true, ages: all}` entry. Both use `{from}`/`{to}`.
   - amz-connect-summary: `command open ... "https://audrey-ops-platform.vercel.app/#sr-ext-repull=connect_summary&from={from}&to={to}"`, guard amazon.
   - markable-spend: `command open ... "#sr-ext-repull=markable_spend&from={from}&to={to}"` (Markable, not Amazon: no guard).
   - meta-daily-metrics: `http /api/cron/meta-sync?from={from}&to={to}`.
   - pulse-daily-snapshots: `http /api/cron/pulse-daily-sync?from={from}&to={to}`.
   - pulse-weekly-stats: the same pulse-daily-sync from/to hook. Its contract says the range rolls up the weeks it
     touches.
   - pulse-signal-scores and pulse-market-health: add `fix_hook` + `http /api/cron/pulse-<x>?from={from}&to={to}`.
     Their existing `?scope=full` recomputes ALL history with delete-by-geo (route.ts:43,56), so it is NOT used as a
     re-pull.
   - tma-cohort-showings: `command open ... "https://throughlinepro.com/#tl-ext-repull=tma&from={from}&to={to}"`.
   - recap-reports: `command ... "#tl-ext-repull=recap&from={from}&to={to}"`.
   - pulse-showings-weekly: the ST hook `#tl-ext-repull=st&from={from}&to={to}` with guard st_brief_sent. Re-ingesting
     the week's days rolls it up.
   - Lost-data series (`historical: "no"`: st-showings-forward, pulse-odds-snapshots, pulse-events-refresh,
     curb-inquiry-results, pulse-member-snapshots) keep no hook. Their gaps escalate as lost dates.
2. **lib/data.sh `_fire`**: substitute `{from}`/`{to}` in http paths, and check them against the ISO regex (as for
   commands). In `data_act`, `to` = the END of the newest gap period: anchor + 6 days for weekly, the last day of
   the month for monthly, the day itself for daily. So weekly and monthly hooks get full date ranges.
3. **Regression tests** (each must FAIL on 275c4b9; archive the fail output and the pass output):
   - (a) a series.yaml contract test: every watched series with historical != "no" has a fix_hook and a
     `requires_fix` method whose command or path contains both `{from}` and `{to}`; every `requires_fix` method
     matches its series' fix_hook trigger;
   - (b) pulse-weekly-stats with a week gap, `hook_merged` true: the hook fires with
     `from` = Monday and `to` = Sunday;
   - (c) meta-daily-metrics with the stub trigger: the http path receives the substituted dates.

## P2 - verify needs a successful fresh count (REAL)
`data_act` step 1 counts a failed try for every REPULLING gap past `verify_at`, even when this tick's count for that
period errored. `data_detect` leaves the gap untouched on an error. So a Supabase outage at verify time burns tries and
can hand the gap to the operator.

### Proposed fix
- `data_detect` records `.gaps[p].counted_at = now` whenever that period was counted successfully.
- `data_act` step 1 fails a try only if `counted_at >= verify_at`; otherwise the verify waits for the next good count.
- Regression (must FAIL on 275c4b9): a REPULLING gap reaches verify_at while its fixture count errors. Expected:
  `failed_tries` stays 0, the state stays REPULLING, and no new trigger fires. The next tick with a real count below
  the floor fails the try exactly once.

## Re-run after the fixes
- `shellcheck -S warning` on all scripts (0).
- Every tests/test-*.sh green (record the new counts).
- `tests/drill/run-data-drill.sh` (must stay 18/18 on the drill topic).
- Codex cycle 2 (final), appended to handoff/codex-review-supervisor-v3-data.md.
- Finish Phase 6:
  - archive the BB 11-14 re-pull, rows before/after from data-repull.log + state;
  - archive the final `walkaway status`;
  - write the phase-6 report.
- Then Phase 7: evidence MANIFEST, PR, CI, and the build report LAST.

## Constraints for the resume
- Live: lib/ runs from this working tree every 120 s with data.enabled ON. Write every lib/ edit atomically: tmp
  file + `mv`/`os.replace`, never in place.
- Tests that use the real data/series.yaml must stub the data operator (tests/fixtures/data/operator-stub.sh). A
  Phase 4 test once spawned real read-only diagnoses from a scratch home; they were killed before deciding.
- Never write, overwrite or delete data rows to test. Never call meta-sync, pulse-signals or pulse-market-health
  live just to test: they rewrite rows.
