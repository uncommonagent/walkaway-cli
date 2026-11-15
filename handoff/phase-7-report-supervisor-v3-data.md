# Phase 7 report - supervisor-v3-data (Codex review, cap 2)

## Cycle 1 (HEAD 275c4b9): 1 P1 + 1 P2 -> STOPPED (d40baff) -> operator approved fix 1 (dbd4dcd) -> fixed in 49377b5
- **P1, executable fix hooks.**
  - data/series.yaml: all 16 watched series with historical != "no" now carry a `fix_hook` and a
    `{requires_fix: true, ages: all}` method with `{from}`/`{to}`. That is the 6 that had one, plus the 10 the
    directive lists. Guards: amazon on amz-connect-summary; st_brief_sent on pulse-showings-weekly.
  - pulse-signals and pulse-market-health use from/to paths, never `?scope=full`.
  - The 5 lost-data series keep no hook.
  - lib/data.sh `_fire`: `{from}/{to}` substituted in http paths as well as commands, after the ISO-date check.
  - lib/data.sh `data_act`: `to` = `_period_end` of the newest gap (weekly anchor+6, monthly last day, daily the day).
- **P2, verify needs a good count.** `data_detect` stamps `counted_at` on every successful count of a gap's period.
  `data_act` fails a try only when `counted_at >= verify_at`. Otherwise it logs "verify ... waits for a successful
  count".
- **Regressions R13-R17** (tests/test-data-repull.sh): 10 FAIL on 275c4b9, 85/85 after.
  - (a) R13: series.yaml contract.
  - (b) R14: pulse-weekly-stats gets from Monday 11-02 to Sunday 11-08.
  - (c) R15: meta-daily-metrics, through the stub AND a real local HTTP server. The route received
    `/api/cron/meta-sync?from=2026-11-08&to=2026-11-09`. A non-ISO date was refused before any request.
  - (d) R16: an errored count at verify leaves 0 tries, the gap REPULLING and no trigger. The next good count fails
    exactly 1 try.
  - (e) R17: for all 16 series, the requires_fix method is never called while hook_merged is false. After a merge it
    fires once wherever no other path covers the gap.
  - Honest note on (e): its per-series "never fires" checks also pass on 275c4b9, because that guard already held.
    On 275c4b9, R17 fails only on its coverage count (16 required; the old yaml has 6 hooks).

## Cycle 2 (HEAD 49377b5, FINAL): 0 P1 + 2 P2 -> no stop, both fixed
- **P2, Amazon pacing re-checked before every trigger.** R18: FAIL on 49377b5, PASS now.
- **P2, date-range hooks fire one range per run of consecutive gaps.** R19: FAIL on 49377b5, PASS now.
- No cycle 3 (cap 2).

## Gates after the cycle-2 fixes (`supervisor-v3-data-evidence/ac5-gates-final.txt`)
- shellcheck -S warning: rc 0.
- 335/335 tests: data-gaps 38, data-operator 25, data-repull 92 (was 33), died-done 12, job-operator 37,
  jobs-states 38, operator 68, parse 7, supervisor-states 18.
- AC3 drill re-run on the final code, 13:15 ET, topic jim-walkaway-data-drill-603a25b7: 18/18, ntfy 8 polled == 8 sent.
- All lib/ and series.yaml edits were written tmp + `os.replace`, because the live supervisor runs this tree.

## Files
- Fix 1 (49377b5): data/series.yaml, lib/data.sh, tests/test-data-repull.sh, tests/fixtures/data/trigger-stub.sh,
  evidence codex1-regressions-*.txt, build log.
- Cycle 2: lib/data.sh, tests/test-data-repull.sh, codex review, this report, evidence codex2-*.txt,
  ac5-gates-final.txt, ac3-drill/ (re-run).
