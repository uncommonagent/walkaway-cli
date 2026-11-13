# Failure report - supervisor-v2-jobs - Phase 7 Codex cycle 1 (P1 stop)

## What stopped
Phase 7 Codex review, cycle 1 (`codex review --base main` at HEAD 4d5c8e2). It returned 1 P1 and 2 P2, all in this
build's diff. The full text and triage are in handoff/codex-review-supervisor-v2-jobs.md. The protocol makes a P1 a
hard stop with a proposed fix for operator triage. No fix has been applied yet.

Phases 0-6 are committed and green:
- AC1-AC5 evidence: handoff/supervisor-v2-jobs-evidence/MANIFEST.md.
- Gates: shellcheck 0; parse 7/7, states 18/18, AC1 12/12, jobs-states 36/36, job-operator 26/26, operator 68/68.
- Live drill 26/26. Job watching has been ON live since 12:13:47 (all jobs OK).

## Live exposure while stopped
Job watching stays on. The P1 race needs two jobs of the same owner repo to fail in the same tick while that repo has
no active build. Today that cannot happen:
- audrey-ops-platform has bf-taste-scoring active, so any fix there only queues.
- throughline's two jobs (showingtime 12:45, realtea Monday 09:15/10:15) have different deadlines.
- Every job is OK for 11/13.

If the operator prefers zero exposure, `./install-supervisor.sh --jobs-off` disables job watching until the fix lands.

## Proposed fixes (all in scope: plan item 4; no PROTECTED action)

1. **P1: serialize fix launches per repository** (lib/registry.sh + lib/job-operator.sh + lib/operator.sh)
   - Add a shared mkdir lock to lib/registry.sh: `queue_lock <repo-key>` / `queue_unlock <repo-key>` at
     `$WALKAWAY_HOME/state/queue-<repo-key>.lock`. It records its pid, waits up to 120 s, and takes over a stale lock
     whose pid is dead.
   - `_queue_or_launch` holds that lock across all of these steps:
     1. append to the queue
     2. `_other_active_build`
     3. remove the plan from the queue
     4. `_sync_default`
     5. the walkaway launch
     6. the wait until the new feature is registered (or the 60 s timeout)
   - `_launch_next` in lib/operator.sh takes the same lock around its queue read/rewrite + launch, so post-merge
     launches and job-fix launches cannot interleave either.
   - Regression test (tests/test-job-operator.sh):
     - Setup: two jobs owned by the same free scratch repo FAIL. Both stub-claude decisions are "fix", with a 2 s
       delay hook, and `diagnose` runs for both concurrently (two background processes).
     - Expected: exactly one fix build registered (launched); the other is queued "behind" it with its plan path
       still in the queue file; the queue file has no lost or duplicated lines.
     - Must fail on 4d5c8e2.

2. **P2: keep following a fix across the daily rollover** (lib/jobs.sh)
   - In `jobs_evaluate`, call `_jobs_fix_progress` whenever the job has `.fix_feature` and `.retry_ran != true`,
     independent of the day's health state (not only while FIXING).
   - `_jobs_rollover` keeps `.fix_feature/.fix_plan/.fix_date/.retry_ran` (it already does) and its last_action says
     "fix <f> still in flight".
   - Regression test (tests/test-jobs-states.sh or test-job-operator.sh):
     - Setup: FIXING on day 1 with a retry command; rollover to day 2; the fix registry entry becomes MERGED on day 2.
     - Expected: the retry runs exactly once on day 2 and the next OK check reports "resolved (failed <day 1>)".
     - Must fail on 4d5c8e2.

3. **P2: a queued (unregistered) fix counts as in flight** (lib/job-operator.sh jo_diagnose)
   - Treat the previous fix as in flight when either condition holds:
     - its registry entry exists and is not MERGED, or
     - no registry entry exists yet and its `.fix_plan` path is still listed in the owner repo's queue file.
   - In that case: transition FIXING "failed again; earlier fix <f> still queued/<state>", with no new plan and no
     change to `.fix_feature`.
   - Regression test:
     - Setup: day-1 fix queued behind a busy build; the job FAILS on day 2.
     - Expected: no second plan, `.fix_feature` unchanged, queue unchanged.
     - Must fail on 4d5c8e2.

Then:
- Re-run every gate: `shellcheck -S warning` on all scripts = 0, all `tests/test-*.sh` green with the new counts.
- Re-run `tests/drill/run-jobs-drill.sh` (it must stay 26/26) and refresh `ac5-gates-final.txt`.
- Commit "Phase 7 fix: Codex cycle 1 P1/P2s".
- Run Codex cycle 2 (the final one); a P1 there stops again.
- Then Phase 8: PR, CI, build report LAST.

## Recommendation for the operator
Approve fixes 1-3 as written. They are mechanical, stay inside plan item 4, touch no PROTECTED action, and each comes
with a fail-before/pass-after regression test.
