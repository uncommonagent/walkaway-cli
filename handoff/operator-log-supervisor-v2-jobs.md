# Operator log - supervisor-v2-jobs

Every supervisor/operator decision for this build, newest last.

## 2026-11-13 12:32 ET - TRIAGE: APPROVE (1/3)
Report: /Users/jimross/Projects/walkaway-cli/handoff/failure-report-supervisor-v2-jobs-codex.md
Rationale: This is Codex cycle 1 of 2. It found 1 P1 and 2 P2s, and all three are concrete bugs in this build's own diff (lib/job-operator.sh, lib/jobs.sh, lib/operator.sh). The fixes carry out plan item 4 as written: one builder per repo, one auto-fix per job per day, and a retry after a fix merges. They add no new feature, change none of the jobs themselves, and touch no PROTECTED action: all diagnosis stays read-only, and the drill uses only the drill ntfy topic and scratch clones. Each fix includes a regression test that must fail on 4d5c8e2 and pass after the fix, and no gate is weakened. Live exposure while the build is stopped is negligible, because no two same-repo jobs can fail together today, so job watching can stay on.
Directive written to the plan:
RESUME DIRECTIVE (operator, 2026-11-13) - supervisor-v2-jobs, Phase 7 Codex cycle 1

What failed: Codex cycle 1 at 4d5c8e2 found 1 P1 and 2 P2. The P1 is that concurrent job operators can both launch into one free repo and their queue rewrites can interleave. The P2s are that fix tracking is lost at the daily rollover, and that a queued fix with no registry entry is not seen as in flight. Details are in handoff/codex-review-supervisor-v2-jobs.md and handoff/failure-report-supervisor-v2-jobs-codex.md.

APPROVED: apply fixes 1-3 exactly as written in failure-report-supervisor-v2-jobs-codex.md.

1. P1, per-repo launch lock.
   - Add `queue_lock <repo-key>` / `queue_unlock <repo-key>` to lib/registry.sh. Use an mkdir lock at $WALKAWAY_HOME/state/queue-<repo-key>.lock. It records its pid, waits up to 120 s, and takes over a stale lock whose pid is dead.
   - `_queue_or_launch` in lib/job-operator.sh holds the lock across six steps: append to the queue, `_other_active_build`, dequeue, `_sync_default`, the walkaway launch, and the wait for registration (or the 60 s timeout).
   - `_launch_next` in lib/operator.sh takes the same lock around its queue read/rewrite and launch.
   - Release the lock on every exit path, including errors and the timeout (use a trap).
   - Regression test in tests/test-job-operator.sh: two concurrent diagnoses for two jobs in the same free scratch repo, both stub-claude decisions "fix", with a 2 s delay. Expected: exactly one fix build registered, the other plan still in the queue file, and no lost or duplicated queue lines.
2. P2, rollover. In lib/jobs.sh, `jobs_evaluate` calls `_jobs_fix_progress` whenever `.fix_feature` is set and `.retry_ran != true`, whatever the day's state. `_jobs_rollover` keeps the fix fields and sets last_action to "fix <f> still in flight". Regression test: the job is FIXING on day 1, rolls over to day 2, and the fix becomes MERGED on day 2. Expected: the retry runs exactly once, then "resolved (failed <day1>)".
3. P2, queued fix counts as in flight. In jo_diagnose, treat the previous fix as in flight in either case: its registry entry exists and is not MERGED, or no entry exists yet and its .fix_plan is still listed in the owner repo's queue file. In that case set FIXING "failed again; earlier fix <f> still queued/<state>": no new plan, `.fix_feature` unchanged, queue unchanged. Regression test: day-1 fix queued behind a busy build, the job FAILS on day 2. Expected: no second plan, nothing changed.

Each new regression test must FAIL on 4d5c8e2. Prove it: run the tests against a 4d5c8e2 checkout in a scratch worktree and archive the fail output plus the pass output after the fix to handoff/supervisor-v2-jobs-evidence/. Add both files to MANIFEST.md.

Re-run:
- `shellcheck -S warning` on all scripts (must be 0).
- Every tests/test-*.sh (all green; record the new counts).
- tests/drill/run-jobs-drill.sh (must stay 26/26, drill ntfy topic only).
- Refresh ac5-gates-final.txt.

Do not weaken or skip any existing test, gate, or acceptance criterion. Make no changes to the jobs themselves. Make no writes to job data tables.

Commit "Phase 7 fix: Codex cycle 1 P1/P2s". Run Codex cycle 2, the final one, and append it to handoff/codex-review-supervisor-v2-jobs.md. A P1 in cycle 2 stops again with a failure report. Then Phase 8: open the PR, wait for CI green, and write the build report LAST.

Then continue the plan from the build log; do not redo committed phases.
