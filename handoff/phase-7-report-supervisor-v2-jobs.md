# Phase 7 report - supervisor-v2-jobs (Codex review, cap 2)

## Cycle 1 (HEAD 4d5c8e2): 1 P1 + 2 P2 → STOPPED → operator approved fix 1 → fixed in fd20bd9
The P1 stopped the build (b8aab8b). The operator approved fixes 1-3 as written (ed8e511). All three are in fd20bd9 ("Phase 7 fix: Codex cycle 1 P1/P2s").

1. **P1, per-repo launch lock.**
   - lib/registry.sh `queue_lock`/`queue_unlock`: mkdir lock at `$WALKAWAY_HOME/state/queue-<key>.lock` holding its pid. It waits up to 120 s (`WALKAWAY_QUEUE_LOCK_WAIT`). A lock whose pid is dead, or that has had no pid for more than 10 s, is taken over.
   - `_queue_or_launch` (lib/job-operator.sh) and `_launch_next` (lib/operator.sh) are now subshell functions that hold the lock across the queue read/append, the active-build check, the dequeue, `_sync_default`, the launch, and the registration wait.
   - An EXIT trap releases the lock on every path. The key is held in a non-local variable so the trap still has it after the locals go out of scope; this bug was found and fixed during the work.
   - If the lock wait times out, `_queue_or_launch` returns `LAUNCH-FAILED` (the job goes to ESCALATED) and `_launch_next` reports the skip.
2. **P2, fix tracking across the rollover.**
   - `jobs_evaluate` calls `_jobs_fix_progress` whenever `.fix_feature` is set and `.retry_ran != true`, whatever the day's state.
   - The old FIXING trigger is kept as well, so the existing jobs-states S1 stub check is unchanged.
   - The call comes after the operator-alive check and before the scheduled-today check. `_jobs_rollover` keeps the fix fields and its last_action says "fix <f> still in flight".
   - Safety addition: if the job is already OK when the merge is first seen (now possible on a later day), `jo_progress` marks the retry done and does not fire the job's retry. `jo_progress` also creates `logs/` before writing the retry log.
3. **P2, a queued fix counts as in flight.**
   - In `jo_diagnose`, a fix with no registry entry whose `.fix_plan` is still in the owner repo's queue file reads as "queued".
   - Result: FIXING "failed again; earlier fix build <f> still queued", with no new plan, `.fix_feature` unchanged and the queue unchanged.

**Regressions J7-J9 (tests/test-job-operator.sh, 11 checks).** On a scratch worktree of 4d5c8e2 the run is 29/37, and all 8 failures are J7-J9. On 4d5c8e2, J7 registered both fix builds into one repo. After the fix the run is 37/37.
- Evidence: `codex1-regression-fail-on-4d5c8e2.txt` and `codex1-regression-pass-after-fix.txt`.

## Cycle 2 (HEAD fd20bd9, final): 0 P1 + 2 P2 → no stop
- **P2 (rollover dropped a running diagnosis's operator_pid): fixed (1 line).**
  - `_jobs_rollover` keeps `.operator_pid`. The operator deletes it on exit.
  - Regression S6c (tests/test-jobs-states.sh) is 37/38 on fd20bd9 (`codex2-regression-fail-on-fd20bd9.txt`) and 38/38 now.
- **P2 (stale-lock takeover race): documented, not fixed.** It is not a one-line fix and the cycle cap is reached. It needs a lock holder killed with SIGKILL plus two waiters on one repo. Logged in ROADMAP.md follow-ups.

## Pre-existing test isolation bug found and fixed
- tests/test-operator.sh failed 66/68 during the 13:00 ET hour. `main` (d3d5af9) fails identically at 13:11 ET.
- Cause: the supervisor's wall-clock 09/13/17 heartbeat repeats the "RUNNING ... active 0m ago" line, which doubles the ntfy counts.
- `WALKAWAY_HEARTBEAT_HOURS=""` does not turn the heartbeat off, because `${VAR:-default}` treats empty as unset. The drill used `""`, so its setting had no effect either.
- Both now set `off`. No assertion changed. The default-handling question is logged to ROADMAP.

## Gates (ac5-gates-final.txt, bash 3.2)
- `shellcheck -S warning` on every script: rc 0.
- Tests: 180/180, all rc 0.

  | Suite | Result |
  |---|---|
  | parse | 7/7 |
  | states | 18/18 |
  | AC1 | 12/12 |
  | jobs-states | 38/38 |
  | job-operator | 37/37 |
  | operator | 68/68 |

- Live drill: 26/26 after the cycle 1 fix (topic jim-walkaway-jobs-drill-fbe389ee, 9 polled == 9 sent). Re-run on the final code (13:25 ET, topic jim-walkaway-jobs-drill-38ee6b0f): 26/26, 9 polled == 9 sent; ac3-drill/ holds this run.

## Deviation: lib edits were made in place
- Phase 0 set the rule "the live launchd supervisor runs lib/ from this tree, so edit in a scratch copy". This phase edited lib/ in place for about 15 minutes (12:36-12:50 ET) before landing.
- Live ticks in that window were checked:
  - no errors in ~/.walkaway-cli/logs/supervisor.log
  - all live jobs OK
  - no lock left behind
  - no queue entries
- No live job failed, so no job operator or queue code path ran live.

## Files
- lib/registry.sh, lib/job-operator.sh, lib/operator.sh, lib/jobs.sh
- tests/test-job-operator.sh, tests/test-jobs-states.sh, tests/test-operator.sh, tests/drill/run-jobs-drill.sh
- ROADMAP.md
- handoff/codex-review-supervisor-v2-jobs.md, this report, the build log
- supervisor-v2-jobs-evidence/{MANIFEST.md, ac5-gates-final.txt, codex1-*, codex2-*, ac3-drill/}
