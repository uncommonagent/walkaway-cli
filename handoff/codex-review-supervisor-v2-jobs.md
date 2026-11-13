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

## Cycle 2 (`codex review --base main`, HEAD fd20bd9, 2026-11-13 12:58 EST) - final cycle (cap 2)

Result: **0 P1, 2 P2.** No stop. Per protocol, a P2 that is a 1-line obvious fix gets fixed; the rest is documented
and logged to ROADMAP follow-ups.

```
codex
Daily rollover can lose tracking of an active diagnosis, allowing conflicting state updates. Stale-lock recovery also retains a race that can defeat per-repository launch serialization.

Full review comments:

- [P2] Preserve a running operator's PID across daily rollover — /Users/jimross/Projects/walkaway-cli/lib/jobs.sh:279-279
  If diagnosis is still running at midnight, rollover deletes its PID before `_jobs_operator_alive` checks it. The supervisor then evaluates the job concurrently with that operator, whose eventual decision still writes to the same state file using yesterday's diagnosis. This can overwrite today's OK state with FIXING or ESCALATED, and permit another diagnosis while the original remains active. Retain the PID until the operator exits, or explicitly stop and reconcile it before resetting the day.

- [P2] Serialize stale-lock takeover before replacing the lock — /Users/jimross/Projects/walkaway-cli/lib/registry.sh:31-33
  When two waiters observe the same stale PID, the first can rename the stale directory and acquire a fresh lock before the second executes `mv`. The second then renames and removes the first waiter's live lock, allowing both callers into the launch critical section. Atomic rename alone does not ensure that the directory being moved is the stale instance that was inspected. Serialize reclamation or otherwise verify ownership safely before replacing it.
```

## Cycle 2 triage
- **P2 (jobs.sh _jobs_rollover drops operator_pid): REAL. FIXED (1-line).**
  - `_jobs_rollover` no longer deletes `.operator_pid`. The diagnosis deletes it itself on exit (job-operator.sh),
    and a dead pid already reads as not alive.
  - So a tick after midnight waits for the running operator instead of evaluating alongside it.
  - Regression S6c (tests/test-jobs-states.sh) fails on fd20bd9 (37/38,
    supervisor-v2-jobs-evidence/codex2-regression-fail-on-fd20bd9.txt) and passes now (38/38, ac5-gates-final.txt).
- **P2 (registry.sh stale-lock takeover race): REAL, narrow. DOCUMENTED, not fixed (not a 1-line fix; cycle cap
  reached).**
  - It needs a lock holder killed with SIGKILL mid-launch plus two waiters on the same repo that inspect the same
    dead pid.
  - Normal and error exits release the lock through the EXIT trap. The P1 from cycle 1 (concurrent live operators)
    stays fixed.
  - Logged to ROADMAP.md follow-ups.
- Codex cycle cap reached: no cycle 3.
