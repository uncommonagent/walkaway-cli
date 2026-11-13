# Codex review - supervisor-v2-jobs

## Cycle 1 (`codex review --base main`, HEAD 4d5c8e2, 2026-11-13 12:31 EST)

Result: **1 P1, 2 P2.** Per protocol the P1 stops the build: failure-report-supervisor-v2-jobs-codex.md proposes the fixes for operator triage. Cycle 2 has not run (cap 2).

```
codex
Concurrent operators can launch builders into the same checkout. Fix tracking also breaks across daily rollover, allowing skipped retries and duplicate queued fixes.

Full review comments:
- [P1] Serialize fix launches per repository — /Users/jimross/Projects/walkaway-cli/lib/job-operator.sh:155-162
  When multiple jobs in the same owner repository fail, their detached operators can finish diagnosis concurrently. Both can observe no registered active build here and launch immediately, since registration happens only after walkaway switches branches. This can switch the checkout underneath another builder and also lose queue entries through concurrent rewrites. Hold a per-repository lock across queue updates, the active-build check, and launch registration.
- [P2] Continue tracking fixes across daily rollover — /Users/jimross/Projects/walkaway-cli/lib/jobs.sh:272-275
  If a daily job's fix merges after midnight, resetting FIXING to PENDING prevents `_jobs_fix_progress` from being called. For ShowingTime this skips the promised post-merge retry; if today's check subsequently fails, diagnosis can instead create another fix because the previous feature is already MERGED. Preserve in-flight fix progression independently of the daily health-state reset.
- [P2] Treat an unregistered queued fix as still in flight — /Users/jimross/Projects/walkaway-cli/lib/job-operator.sh:197-200
  If a fix remains queued behind another build overnight and the job fails again the next day, `registry_get` returns no state for that queued feature. Neither guard matches, so another fix plan is queued and `.fix_feature` is overwritten. The original plan remains runnable but is no longer tracked for post-merge confirmation or retry. Check the queue or retained fix-plan tracking before allowing another fix, rather than requiring an existing registry entry.
```

## Triage
- **P1 (job-operator.sh _queue_or_launch): REAL.** Two detached job operators for two jobs in the same owner repo can both pass the active-build check before either registers, so both launch into one checkout. Their queue rewrites (append + awk/mv) can also interleave. Fix proposed (failure report, fix 1).
- **P2 (jobs.sh _jobs_rollover): REAL.** A FIXING job reset to PENDING at midnight stops calling progress. A fix merged after midnight then never runs the retry, and a new failure can start a second fix. Fix proposed (fix 2).
- **P2 (job-operator.sh jo_diagnose in-flight guard): REAL.** A fix plan still queued (not yet registered) is not treated as in flight, so a next-day failure queues a second plan and overwrites .fix_feature. Fix proposed (fix 3).
