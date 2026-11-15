# Evidence MANIFEST - supervisor-v3-data

Each acceptance criterion in handoff/build-plan-supervisor-v3-data.md is listed with the files that prove it. Paths are
relative to handoff/supervisor-v3-data-evidence/ unless noted otherwise.

Source of truth (spot check): each series' own table in the Showrunner and Throughline Supabase projects
(amazon_tracking_daily, amazon_creator_connections_daily, amazon_sponsored_products_daily,
amazon_connect_summary_daily, pulse_showings_daily, pulse_bb_showings_daily, pulse_* tables, ...). Every row count in
the dumps is an exact-count REST GET (`Prefer: count=exact`), and the query is printed next to it so a gate can re-run it.

## AC1: series.yaml covers every scheduled pull/cron found in Phase 0 (inventory vs yaml diff = 0), each with a real passing check dumped
- `phase0-inventory.md` / `phase0-inventory.txt`: 49 scheduled pulls/crons across Showrunner and Throughline (extension
  tools, Vercel crons, Showrunner report types). 21 are watched series; 28 are excluded with a reason (not a dated
  series, a notifier, or a duplicate writer of a watched table).
- `../../data/series.yaml`: 49 entries (21 watched, 28 excluded).
- `ac1-inventory-diff-final.txt` (13:48 ET, final yaml): `rc=0 ids=49 yaml=49 watched=21`, so the diff is empty. The
  earlier `ac1-inventory-diff.txt` (12:22) shows the same result.
- `ac1-series-check-dump-final.md` (13:48 ET, final yaml): 21/21 watched series PASS on real exact counts, with 14
  periods each, the query, the floor and its derivation. bb-showings-daily PASSes as of 2026-11-09 14:00 ET, its last
  complete day. Its real gap since then is AC4. Earlier dumps: `ac1-series-check-dump-phase1.md`, `ac1-series-check-dump.md`.
- `phase0-floors.tsv`, `ac1-floors-rederived.tsv`: floors derived from the last 30 days of real rows (50% of median,
  or structural where every day is equal).

## AC2: tests for gap detection (missing, short, lag-aware, weekday cadence), retry window, re-pull cap, escalation on no re-pull path
- tests/test-data-gaps.sh 38/38: missing, short, lag/ready_by, weekday and weekly cadence, cached complete periods,
  daily full scan, error escalation, real-incident fixtures (odds 10-15..10-18 missing, cc 10-22 short).
- tests/test-data-repull.sh 92/92: method by age, retry window, Amazon hours / CC batch / pacing, 2-try cap, verify ->
  CLOSED, no path -> operator. Regressions R11-R19 included.
- tests/test-data-operator.sh 25/25: no path -> fix plan (template v2 with the date-range hook contract) or one
  question, lost data -> ESCALATED with the lost dates, post-fix re-pull.
- Record: `ac5-gates-final.txt`.
- Fail-before/pass-after regression records: `phase6-regression-R11-fail-on-159fbbc.txt`,
  `phase6-regression-R12-fail-on-159fbbc.txt`, `phase6-regression-R11-R12-pass-after-fix.txt`,
  `codex1-regressions-fail-on-275c4b9.txt` / `codex1-regressions-pass-after-fix.txt` (R13-R17),
  `codex2-regressions-fail-on-49377b5.txt` / `codex2-regressions-pass-after-fix.txt` (R18-R19).

## AC3: delete-free drill on a scratch series: OPEN -> re-pull stub -> CLOSED; failing re-pull -> fix plan queued; exactly one ntfy per transition (drill topic)
Drill directory: `ac3-drill/`, from tests/drill/run-data-drill.sh on the final code (13:13-13:15 ET, topic
jim-walkaway-data-drill-603a25b7): 18/18. It used real supervisor ticks, real `claude -p` and real ntfy, with fixture
rows only (nothing deleted).

| Requirement | Evidence |
|---|---|
| OPEN -> re-pull stub -> CLOSED | `drill-transcript.txt` (drill-repull), `state/drill-repull.json`, `data-repull.log` |
| Failing re-pull -> fix plan queued | `job-incident-drill-nopath-2026-11-18.md`, `build-plan-fix-data-drill-nopath-20261118.md` (template v2, `--from/--to` hook contract), `evidence-drill-nopath-2026-11-18.json`, `data-operator.log`. QUEUED behind drill-busy, then after a simulated merge the hook fired once for 2026-11-12 and the gap went CLOSED (`state/drill-nopath.json`) |
| Lost source -> ESCALATED with lost dates | `job-incident-drill-lost-2026-11-18.md`, `state/drill-lost.json` |
| Exactly one ntfy per transition | `ntfy-poll.json` / `ntfy-poll-messages.tsv` (8 polled) == `ntfy-local.log` (8 sent). drill-repull [OPEN CLOSED], drill-nopath [OPEN FIXING CLOSED], drill-lost [OPEN ESCALATED]; REPULLING never pinged; ESCALATED is priority 4 |

Supporting files: `supervisor-data-transitions.log`, `walkaway-status-drill.txt`, `drill-series.json`, `pull-drill.txt`.

## AC4: live detector over the real last 14 days; real gaps re-pulled and closed or escalated with reason; rows before/after per gap
- `ac4-live/gap-report-14d-before-enable.md` (12:22 ET): the 14-day gap report on real rows. 20 series are complete.
  bb-showings-daily is missing 2026-11-09..11-13 (0/10 rows each). 11-14 was not ready until 13:00.
- `ac4-live/enable-and-reload.txt`: `install-supervisor.sh --data-on` at 12:35:05, then the launchd reload.
- `ac4-live/supervisor-data-lines.log`, `ac4-live/ntfy-live-data-lines.log`: the first live tick at 12:35:16 opened
  11-09..11-13 (one ntfy on Jim's topic). The data operator ran at 12:36:09 and ESCALATED with one question (priority high).
- `ac4-live/job-incident-bb-showings-daily-2026-11-15.md`: the cause is a dead BrokerBay session. `maybeRunBbAfterSt`
  drops needsLogin silently (`bb-core.js:908-911`, `background.js:228-233`). The dates are NOT lost, because BrokerBay
  re-pulls 90 days, but they need a sign-in, which is a credential and therefore escalated.
- `ac4-live/state-bb-showings-daily-1236.json`: the state at 12:36.
- `ac4-live/bb-1114-repull.md`: the live 11-14 re-pull, with rows before/after per gap, the trigger lines, the
  verify lines and the final state. See "Per-gap rows before/after" below.
- `ac4-live/state-bb-showings-daily-final.json`: the final state file.
- `ac4-live/http-path-probe.md`, `ac4-live/run-now-target-rows.jsonl`: the live re-pull paths were probed read-only
  (R11 came from this).

### Per-gap rows before/after (pulse_bb_showings_daily, is_total=true, floor 10)
| Gap | Rows before | Rows after | Outcome |
|---|---|---|---|
| 2026-11-09 | 0 | 0 | ESCALATED: BrokerBay login (credential); re-pullable once signed in |
| 2026-11-10 | 0 | 0 | ESCALATED (same) |
| 2026-11-11 | 0 | 0 | ESCALATED (same) |
| 2026-11-12 | 0 | 0 | ESCALATED (same) |
| 2026-11-13 | 0 | 0 | ESCALATED (same) |
| 2026-11-14 | 0 | 0 | Live re-pull fired twice (13:01, 13:47) through the extension daily run; both verifies 0 rows; ESCALATED 14:34:33 with one question (BrokerBay sign-in). Re-pullable once signed in |

## AC5: supervisor reloaded; `walkaway status` shows JOBS + DATA tables (archived); shellcheck 0, tests green
- `ac4-live/enable-and-reload.txt`: launchd bootout + bootstrap + enable at 12:35:07.
- `ac4-live/walkaway-status-live.txt` (12:36) and `ac4-live/walkaway-status-final.txt` (final): the builds table,
  JOBS and DATA.
- `ac5-gates-final.txt`: `shellcheck -S warning` rc 0. Results: data-gaps 38, data-operator 25, data-repull 92,
  died-done 12, job-operator 37, jobs-states 38, operator 68, parse 7, supervisor-states 18 = 335/335. A re-run at
  report time is recorded in `ac5-gates-report-time.txt`.

## Codex
- `../codex-review-supervisor-v3-data.md`: cycle 1 (1 P1 + 1 P2, both fixed) and cycle 2 (final; 0 P1, 2 P2, both
  fixed). Raw cycle 2 output: `codex2-raw-output.txt`.
