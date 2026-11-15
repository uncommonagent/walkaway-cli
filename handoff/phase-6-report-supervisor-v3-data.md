# Phase 6 report - supervisor-v3-data (live smoke) - COMPLETE (finished 2026-11-15 14:40 ET after the Codex fixes)

- **AC1 (real rows):** `supervisor-v3-data-evidence/ac1-series-check-dump.md`, 2026-11-15 12:22 ET.
  - 21/21 watched series PASS on real exact counts. bb-showings-daily PASSes as of 2026-11-09 14:00; today it shows
    its real gap.
  - 28 excluded entries carry a reason, and a real probe row where a table exists.
  - Inventory diff 0, 49 = 49 (`ac1-inventory-diff.txt`). Floors re-derived from real rows (`ac1-floors-rederived.tsv`).
- **AC3 drill** (`ac3-drill/`, 12:22-12:23 ET, topic jim-walkaway-data-drill-045f6ee7): 18/18.
  - Real supervisor ticks with data watching on. Delete-free fixture series.
  - drill-repull went OPEN -> re-pull fired -> CLOSED (rows 0 -> 12).
  - drill-nopath: the yesterday-only pull failed twice, then REAL `claude -p` decided "fix" at high confidence, citing
    `scripts/pull.sh:17`. The template-v2 plan carries the `--from/--to` hook contract verbatim and was QUEUED behind
    drill-busy. After a simulated merge the hook fired once for exactly 2026-11-12, and it went CLOSED (rows 0 -> 12).
  - drill-lost went OPEN -> ESCALATED: "lost 2026-11-16 (0/4 rows): the source cannot re-pull a past day...", priority high.
  - ntfy: 8 messages polled == 8 sent locally. Transitions: drill-repull [OPEN CLOSED], drill-nopath [OPEN FIXING
    CLOSED], drill-lost [OPEN ESCALATED]. REPULLING never pinged.
- **Live findings, fixed with regression tests** (commit d02faa6; R11 and R12 fail on 159fbbc and pass now):
  - **R11, http trigger.** The live `pulse-daily-sync?ifMissing=1` answers 200 `{"skipped":"yesterday's snapshots
    already present"}` only after 42.8 s. Our 30 s timeout read HTTP 000, and that was counted as a fired re-pull,
    the same as an unreachable route. Now: curl exit 28 = delivered (the verify step decides); any other curl
    failure = a failed try; the default timeout is 60 s. `pulse_sync_state.updated_at` stayed 08:18:32Z: no sync
    ran (`ac4-live/http-path-probe.md`).
  - **R12, brief send.** The ST daily ingest sends the day's Pulse brief when it hasn't gone out yet
    (daily-ingest/route.ts:90-95). Every ST URL trigger and ST/BB fix hook now has guard `st_brief_sent`: fire
    only once today's `pulse_brief_sends` row exists. A re-pull never fires a send.
- **AC4 live** (`ac4-live/`):
  - **12:22, before enable:** 14-day gap report (`gap-report-14d-before-enable.md`): 20 series complete; bb-showings-daily
    11-09..11-13 missing (0/10 rows); 11-14 not ready until 13:00. The run-now targets exist, one base row per
    allow-listed type (`run-now-target-rows.jsonl`).
  - **12:35:05:** `./install-supervisor.sh --data-on`. 12:35:07: launchd bootout + bootstrap + enable
    (`enable-and-reload.txt`).
  - **12:35:16, first live tick:** `data: bb-showings-daily: 2026-11-09..11-13 -> OPEN - 2026-11-09..11-13 missing
    (0/10 rows)`, one ntfy on Jim's topic. No path covers ages 2-6, so the gaps went to the data operator.
  - **12:36:09:** the real diagnosis ran read-only in throughline-app (confidence medium, protected_hit true).
    - Cause: the BB code is unchanged since 11-08 and ST runs daily. A dead BrokerBay session sets bb_login and
      returns needsLogin, which `maybeRunBbAfterSt` drops silently (`bb-core.js:908-911`, `background.js:228-233`).
    - Result: ESCALATED, priority high, ONE question: "On the Mini, what does the extension popup's BrokerBay status
      say? If it says BB login needs attention, is BrokerBay logged out in Chrome and can you sign it back in?"
    - The dates are not lost: BrokerBay re-pulls 90 days. Rows before/after: 0 -> 0 for 11-09..11-13 (escalated,
      not re-pullable without a login).
    - Incident: `~/.walkaway-cli/data-fixes/bb-showings-daily-2026-11-15/handoff/job-incident-bb-showings-daily-2026-11-15.md`.
  - **13:01-14:34, BB 2026-11-14 live re-pull** (`ac4-live/bb-1114-repull.md`):
    - 13:01:32: OPEN (0/10 rows), one ntfy.
    - 13:01:34: try 1, `#tl-ext-run-daily` (guard st_brief_sent passed). REPULLING sent no ntfy.
    - 13:47:30: verify failed (0 rows). 13:47:31: try 2.
    - 14:33:25: verify failed again (0 rows; counted_at >= verify_at, so the P2 fix held live) -> 2-try cap -> data operator.
    - 14:34:33: ESCALATED, priority high, ONE question: "On the Mini's Chrome, is edge.brokerbay.com signed in? ..."
      (`ac4-live/job-incident-bb-showings-daily-2026-11-15-final.md`).
    - Rows before/after (exact counts, `ac4-live/bb-check-1436.json`, 14:36): 11-08 = 21 (last complete);
      11-09..11-14 = 0 -> 0. All six are ESCALATED, not lost: BrokerBay re-pulls 90 days once signed in.
    - Final state: `ac4-live/state-bb-showings-daily-final.json`. Logs: `ac4-live/supervisor-data-lines-final.log`,
      `ac4-live/ntfy-live-data-lines-final.log` (4 live data ntfy: 2 OPEN, 2 ESCALATED).
- **AC1 final** (13:48 ET, final yaml): `ac1-series-check-dump-final.md` 21/21 PASS; `ac1-inventory-diff-final.txt`
  rc 0, 49 = 49, 21 watched.
- **AC5:**
  - `ac4-live/walkaway-status-live.txt` (12:36) and `ac4-live/walkaway-status-final.txt` (14:36) show the builds
    table, JOBS and DATA. In the final DATA table, 20 series read "no gaps (checked 14:35)" and bb-showings-daily
    shows 11-09..11-14 ESCALATED with the question.
  - Gates at report time (`ac5-gates-report-time.txt`, 14:30): shellcheck 0, 335/335.
- **Codex cycle 1 = 1 P1 + 1 P2 (both real)** stopped the build at 275c4b9 (failure-report-supervisor-v3-data-codex.md).
  Both were fixed in Phase 7 (49377b5) before this smoke was finished.
- Gates at 275c4b9: shellcheck 0; 276/276 (data-gaps 38, data-operator 25, data-repull 33, parse 7, states 18,
  v2-AC1 12, jobs-states 38, job-operator 37, operator 68).
