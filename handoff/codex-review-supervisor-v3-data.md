# Codex review - supervisor-v3-data

## Cycle 1 (`codex review --base main`, HEAD 275c4b9, 2026-11-15 12:47 EST)

Result: **1 P1, 1 P2, both REAL.** Per protocol the P1 stops the build: failure-report-supervisor-v3-data-codex.md proposes the fixes for operator triage. Cycle 2 has not run (cap 2).

```
codex
Some advertised post-fix recovery hooks cannot be executed by the supervisor. Count outages also incorrectly consume verification failures and can initiate unnecessary remediation.

Full review comments:
- [P1] Register executable re-pull hooks for the remaining fix contracts — /Users/jimross/Projects/walkaway-cli/data/series.yaml:347-348
  For a missing historical week in `pulse-weekly-stats`, the operator can build and merge the advertised hook, but `repull` remains empty, so `_method_for` still returns `none` after the merge. The supervisor never invokes the new hook and escalates instead of recovering the data. Several other entries likewise advertise `fix_hook` without a corresponding `requires_fix` method. Add executable methods for those contracts, including substitution of `{from}` and `{to}` in HTTP paths.
- [P2] Require a successful fresh count before failing verification — /Users/jimross/Projects/walkaway-cli/lib/data.sh:660-663
  If the count request fails when `verify_at` expires, `data_detect` leaves the gap REPULLING and returns successfully. This selection then treats the stale count as a confirmed failed re-pull, increments `failed_tries`, and can trigger another pull or an unnecessary fix build during a database outage. Defer verification for periods whose current count errored rather than consuming a try without observing their rows.
```

## Triage
- P1 REAL: data/series.yaml advertises fix_hook on amz-connect-summary, markable-spend, meta-daily-metrics, pulse-daily-snapshots, pulse-weekly-stats, tma-cohort-showings, recap-reports with no requires_fix method, so after such a fix merges _method_for returns none and data-operator rule 2 escalates instead of re-pulling. _fire substitutes {from}/{to} only in commands, not http paths; weekly/monthly hooks would get the period anchors, not the period's full date range.
- P2 REAL: data_act step 1 counts a failed try for any REPULLING gap past verify_at, even when this tick's count for that period errored (data_detect leaves the gap untouched on error), so a Supabase outage at verify time burns tries and can hand off to the operator.

## Resolution of cycle 1 (operator approved fix 1, commit 49377b5)
- P1 fixed: series.yaml gives every watched series with historical != "no" a fix_hook and a `requires_fix`
  `{from}/{to}` method (16 series). `_fire` substitutes `{from}/{to}` in http paths after the ISO check. `to` is the
  end of the newest gap period (weekly Sunday, monthly last day).
- P2 fixed: `data_detect` stamps `.gaps[p].counted_at` on every successful count. Verify fails a try only when
  `counted_at >= verify_at`.
- Regressions R13-R17 (a-e) in tests/test-data-repull.sh: 10 FAIL on 275c4b9, 85/85 after
  (`supervisor-v3-data-evidence/codex1-regressions-*.txt`).

## Cycle 2 - FINAL (`codex review --base main`, HEAD 49377b5, 2026-11-15 13:06 EST)

Result: **0 P1, 2 P2, both REAL, both fixed.** No stop. No cycle 3 (cap 2).
Raw output: `supervisor-v3-data-evidence/codex2-raw-output.txt`.

```
codex
The re-pull execution loop can bypass Amazon pacing and request complete dates between separated gaps. Both issues affect the safety boundaries of automatic recovery.

Full review comments:

- [P2] Recheck Amazon guards immediately before each trigger — /Users/jimross/Projects/walkaway-cli/lib/data.sh:727-728
  When an Amazon series has both a recent gap covered by run-now and an older gap covered by an already-merged fix hook, both methods pass the pacing guard during planning, before either fires. This loop then fires both immediately, despite the first trigger updating `_amazon_last_trigger`. Recheck the guard before each `_fire` and defer subsequent groups without consuming a try so the configured 15-minute pacing limit actually holds.

- [P2] Split nonconsecutive gaps into separate re-pull ranges — /Users/jimross/Projects/walkaway-cli/lib/data.sh:725-726
  When gaps assigned to the same date-range hook are separated by complete periods, taking the oldest and newest anchors re-pulls every intervening period too. For example, gaps on November 4 and November 8 produce a November 4–8 request, including three dates already confirmed complete. Partition the selected periods into consecutive ranges before firing hooks to honor the exact-gap-date contract and avoid unnecessarily rewriting complete data.
```

## Triage + fixes (cycle 2)
- P2 Amazon pacing REAL. The guard was checked only while planning, so two Amazon methods could fire in one tick.
  Fix: data_act step 3 re-runs `_amazon_guard` right before every Amazon trigger. A deferral costs no try, and its
  wait reason goes to the log and last_action. Regression R18: FAIL on 49377b5 (2 triggers in one tick), PASS now.
- P2 non-consecutive ranges REAL. It violated the plan's "exactly the gap dates". Fix: a method whose command or path
  holds `{from}`/`{to}` fires once per run of consecutive periods. A trigger without dates (the ST URL trigger,
  run-now, self-heal) still fires once for all of its gaps. Regression R19: FAIL on 49377b5 (one 11-04..11-08
  call), PASS now (11-04..11-04 + 11-07..11-08).
- Evidence: `codex2-regressions-fail-on-49377b5.txt` (88/92), `codex2-regressions-pass-after-fix.txt` (92/92).
