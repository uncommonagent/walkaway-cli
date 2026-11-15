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
