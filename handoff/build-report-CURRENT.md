# Build Report: supervisor-v3-data

Branch `feature/supervisor-v3-data`, PR #3 (https://github.com/uncommonagent/walkaway-cli/pull/3): OPEN, CLEAN, MERGEABLE.
Plan: handoff/build-plan-supervisor-v3-data.md. Evidence index: handoff/supervisor-v3-data-evidence/MANIFEST.md.

Build started: 2026-11-15 11:13 ET (plan commit bf81919). Build ended: 2026-11-15 14:45 ET.
Status: COMPLETE. Along the way: 1 Codex STOP, approved and fixed; 1 auto-resume after a 40-min stall at 13:48.

## TL;DR
- **The supervisor now watches every dated data series in Showrunner and Throughline.**
  - Phase 0 inventoried 49 scheduled pulls/crons: 21 watched series, 28 excluded with a reason.
  - Each watched series is counted against its own table every tick over 14 days.
  - Missing or short days past their retry window become gaps. The supervisor re-pulls them through the job's own path
    (paced, with Amazon guards, max 2 tries) and verifies the rows landed.
  - When a gap can't be re-pulled, the data operator writes a fix build (date-range hook) or escalates one question.
  - `walkaway status` has a DATA table.
- **Live since 12:35 ET today.** It found one real gap: BrokerBay showings 11-09..11-14, 0 rows each.
  - The 11-14 re-pull fired twice live and both verifies found 0 rows.
  - The operator traced it to a BrokerBay session that appears signed out. The extension drops `needsLogin` silently,
    which is why it went unnoticed for six days.
  - It is ESCALATED with one question, because signing in is a credential action. The dates are not lost (BB re-pulls 90 days).
- **Gates:** shellcheck 0. 335/335 tests. Drill 18/18 (real `claude -p`, ntfy 8 polled == 8 sent). Codex 2 cycles, all
  4 findings fixed with fail-before/pass-after regressions.
- **Jim:** sign BrokerBay back in on the Mini (question below). The merge gate handles PR #3.

## Acceptance criteria
| AC | Status | Evidence (handoff/supervisor-v3-data-evidence/) |
|---|---|---|
| AC1 series.yaml covers every pull/cron (diff 0), each with a real passing check dumped | PASS | `ac1-inventory-diff-final.txt` (rc 0, 49 = 49, 21 watched), `ac1-series-check-dump-final.md` (21/21 PASS, exact counts, queries printed), `phase0-inventory.md`, `../../data/series.yaml` |
| AC2 tests: missing, short, lag-aware, weekday cadence, retry window, re-pull cap, escalation on no path | PASS | `ac5-gates-final.txt`, `ac5-gates-report-time.txt`: data-gaps 38, data-repull 92, data-operator 25 |
| AC3 delete-free drill: OPEN -> stub -> CLOSED; failing re-pull -> fix plan queued; one ntfy per transition | PASS | `ac3-drill/` (13:15 ET on the final code, topic jim-walkaway-data-drill-603a25b7: 18/18, 8 polled == 8 sent) |
| AC4 live 14-day detector; real gaps re-pulled and closed or escalated with reason; rows before/after | PASS (escalated with reason) | `ac4-live/gap-report-14d-before-enable.md`, `ac4-live/bb-1114-repull.md`, `ac4-live/bb-check-1436.json`, `ac4-live/state-bb-showings-daily-final.json`, both incident files |
| AC5 supervisor reloaded; status shows JOBS + DATA; shellcheck 0; tests green | PASS | `ac4-live/enable-and-reload.txt`, `ac4-live/walkaway-status-final.txt` (14:36), `ac5-gates-report-time.txt` |

## Phases executed
| Phase | Commit | Result |
|---|---|---|
| 0 Inventory | 7b9d01c | 49 pulls/crons -> 21 watched + 28 excluded; floors from real rows; real BB gap seen. Baseline shellcheck 0, 180/180 |
| 1 series.yaml + count engine | 20700ca | 49 entries, diff 0; 20/21 PASS live (BB = real gap); shellcheck 0, 180/180 |
| 2 Gap detector + states | 9ad0db6 | OPEN/CLOSED, lag/cadence/floors, grouped ntfy, heartbeat; data-gaps 32/32; 212/212 |
| 3 Re-pull executor | 793ce7f | run-now / http / command / self-heal, Amazon guards, 2-try cap; data-repull 28/28; 240/240 |
| 4 Data operator + hooks + DATA table | e4355d6 | Fix plan or one question, post-fix re-pull, gated supervisor hooks; 271/271 |
| 5 Tests, drill, installer, README | 159fbbc | AC2 matrix, AC3 drill harness, `--data-on/--data-off`; 272/272 |
| 6 Live smoke | d02faa6, 275c4b9, 17ded70 | Live fixes R11 (http timeout) and R12 (ST brief send) with regressions; data ON 12:35; BB gap OPEN -> ESCALATED; BB 11-14 re-pulled twice -> ESCALATED 14:34:33 |
| 7 Codex cycle 1 | d40baff (STOPPED) -> dbd4dcd (approved) -> 49377b5 | P1 executable fix hooks with {from}/{to}; P2 verify needs a good count; R13-R17 (10 FAIL on 275c4b9, pass after) |
| 7 Codex cycle 2 (final) | 1fb0889, 5027b47 | 0 P1; 2 P2 fixed (Amazon pacing re-checked per trigger; one range per consecutive gap run); R18/R19 |
| 8 PR + report | PR #3 + this commit | OPEN, CLEAN, MERGEABLE; no CI configured |

## Files changed (main...HEAD: 81 files, +14517/-3; most are evidence and fixtures)
- **Phase 0:** handoff only (inventory, floors).
- **Phase 1:** data/series.yaml (new), lib/data.sh (new).
- **Phase 2:** lib/data.sh, data/series.yaml, tests/test-data-gaps.sh (new).
- **Phase 3:** lib/data.sh, data/series.yaml, tests/test-data-repull.sh (new), tests/test-data-gaps.sh.
- **Phase 4:**
  - lib/data-operator.sh (new), templates/data-operator-prompt.md (new)
  - lib/data.sh, lib/supervisor.sh (+12/-1, gated hooks), walkaway.sh (+2/-1, DATA table)
  - tests/test-data-operator.sh (new), tests/test-data-gaps.sh, tests/test-data-repull.sh
- **Phase 5:** README.md, install-supervisor.sh (`--data-on/--data-off`), tests/drill/run-data-drill.sh (new),
  lib/data.sh, tests/test-data-repull.sh, .gitignore.
- **Phase 6:** lib/data.sh, lib/data-operator.sh, tests/test-data-repull.sh, evidence.
- **Phase 7:** data/series.yaml, lib/data.sh, tests/test-data-repull.sh, tests/fixtures/data/trigger-stub.sh,
  README.md, codex review, evidence.
- **Final totals:**

  | File | Lines |
  |---|---|
  | lib/data.sh | +903 |
  | data/series.yaml | +504 |
  | tests/test-data-repull.sh | +312 |
  | lib/data-operator.sh | +248 |
  | tests/drill/run-data-drill.sh | +234 |
  | tests/test-data-operator.sh | +166 |
  | tests/test-data-gaps.sh | +165 |
  | README.md | +59 |
  | templates/data-operator-prompt.md | +51 |
  | install-supervisor.sh | +14/-1 |
  | lib/supervisor.sh | +12/-1 |
  | walkaway.sh | +2/-1 |

## Migrations applied
None. No database writes: every Supabase access is a read-only exact-count GET. No rows were written, overwritten or deleted.

## Tests added
- 155 new checks: tests/test-data-gaps.sh 38, tests/test-data-repull.sh 92, tests/test-data-operator.sh 25.
- Live drill: tests/drill/run-data-drill.sh, 18 checks.
- Regressions R11-R19 are pinned in test-data-repull.sh, each with an archived run that fails on the pre-fix commit.
- Existing suites unchanged and green: 180.

## Codex review summary
`handoff/codex-review-supervisor-v3-data.md`.
- Cycle 1 (275c4b9) found:
  - P1: fix hooks had no executable method and http paths lacked {from}/{to}.
  - P2: verify consumed a try when the count errored.
  - Both were fixed after operator approval (49377b5).
- Cycle 2 (final, 49377b5) found 0 P1 and 2 P2: Amazon pacing per trigger, and one range per consecutive gap run.
  Both were fixed (1fb0889).
- Honest note: R17's "never fires before merge" checks also pass on 275c4b9, because that guard already held. It
  fails there only on hook coverage (6 vs 16).
- No remaining Codex findings.

## Smoke test results (real system, Mac mini, 2026-11-15)
- **Real counts:** 21/21 watched series PASS (13:48 ET). Examples:
  - amazon_tracking_daily offsite, 2026-11-14: 39 rows (floor 13).
  - pulse_bb_showings_daily is_total, 2026-11-08: 21 rows.
- **Live detection:** 12:35:16, `bb-showings-daily: 2026-11-09..11-13 -> OPEN (0/10 rows)`, one ntfy on Jim's topic.
  12:36:09 ESCALATED (priority high).
- **Live re-pull:**
  - 13:01:34 and 13:47:31: `open ... #tl-ext-run-daily for 2026-11-14..2026-11-14 (rows before: 0)`.
  - Verify 13:47:30 and 14:33:25: 0 rows -> data operator -> ESCALATED 14:34:33.
  - Rows after (14:36): 11-09..11-14 = 0, 11-08 = 21.
- **Live http path probe (R11):** `pulse-daily-sync?ifMissing=1` returned 200 `{"skipped":"yesterday's snapshots
  already present"}` after 42.8 s. That is why the timeout is now 60 s, and why curl exit 28 counts as delivered.
- **Final `walkaway status`:** 14:36, `ac4-live/walkaway-status-final.txt`. 20 series read "no gaps (checked 14:35)";
  bb-showings-daily shows 11-09..11-14 ESCALATED.

## Known issues / deferred
- **BrokerBay gap 11-09..11-14 is open (ESCALATED), waiting on Jim's sign-in.** The backfill needs the
  `#tl-ext-repull=bb` fix build in throughline-app (its contract is in series.yaml). After that merges, the supervisor
  re-pulls the six days as one range.
- **No CLI path to answer a data ESCALATED.** Build escalations are answered with a plan directive and
  `walkaway --force`. A data escalation has no plan yet, so today the answer means queuing the fix plan by hand.
  Candidate for supervisor-v4: let `walkaway answer <series> "<text>"` re-run the data operator with Jim's answer.
- **Follow-up (owner repo, not built):** the Throughline extension's `maybeRunBbAfterSt` drops `needsLogin` /
  bb_error results silently (background.js:229, bb-core.js:885-914). This build now catches the symptom (a gap) the
  next day. Making the extension itself report a BB login loss is a change to how pulls work, which the plan's
  "Do NOT build" excludes. It belongs in a throughline-app plan.
- **The operator's two questions differ in wording** (12:36 popup status vs 14:34 edge.brokerbay.com sign-in), so Jim
  got 2 ESCALATED pings for the same root cause, one per gap batch (11-09..13, then 11-14). Each is one ntfy per
  transition, as designed. A future refinement could join a new gap into an existing open escalation for the same
  cause.
- **The builder stalled 40 min after 13:48** (the remaining work was waiting on the 14:32 verify). The supervisor
  auto-resumed it (1/2), and this session finished it.

## Branch / PR
`feature/supervisor-v3-data` -> PR #3 https://github.com/uncommonagent/walkaway-cli/pull/3. State OPEN, mergeable
MERGEABLE, mergeStateStatus CLEAN. Not merged; the merge gate does that.

## CI result
No CI is configured: 0 workflows (`gh api repos/uncommonagent/walkaway-cli/actions/workflows` total_count 0).
`gh pr checks 3` reports "no checks reported", the same as PRs #1 and #2. The local gates are the record:
`ac5-gates-report-time.txt` (14:30 ET, bash 3.2) shows shellcheck rc 0 and 335/335.

## What Jim should do next
1. **Answer the BrokerBay question:** on the Mini's Chrome, is edge.brokerbay.com signed in? If not, sign in once.
   - Any gap whose rows then land closes on its own: the next tick sends one CLOSED ntfy (data_detect closes any
     non-CLOSED gap at/above the floor).
   - Days the normal daily run doesn't re-cover need the BB date-range hook, which isn't built yet.
   - To backfill them, have Claude queue the throughline-app fix plan from the incident at
     `~/.walkaway-cli/data-fixes/bb-showings-daily-2026-11-15/handoff/job-incident-bb-showings-daily-2026-11-15.md`.
     Its contract is series.yaml `fix_hook` `#tl-ext-repull=bb`.
   - After that merges, the supervisor re-pulls 11-09..11-14 as one range.
   - This build has no command for "answer a data escalation". That is a gap in the CLI; see deferred.
2. Nothing else is required. The merge gate verifies MANIFEST.md and merges PR #3. Data watching stays ON.
3. Optional: queue a throughline-app plan so the extension reports BB login loss itself (see deferred).
