# Operator log - build-supervisor

Every supervisor/operator decision for this build, newest last.

## 2026-11-12 15:37 ET - TRIAGE: APPROVE (1/3)
Report: /Users/jimross/Projects/walkaway-cli/handoff/failure-report-build-supervisor-codex.md
Rationale: I checked all five fixes against the plan. Each one corrects a concrete defect in operator or supervisor code that plan items 2 and 3 require, and none of them changes how builders run phases. Fix 1 still deletes the branch after the merge, which plan item 3 already requires; it just moves the worktree prune and branch delete to after a confirmed merge. The P1s are code defects, not design or scope questions, and no protected action is involved. I added the obvious missing pieces: a regression test for a failed merge in a worktree build, shellcheck/test gates, and the rule that Codex cycle 2 is the last one.
Directive written to the plan:
RESUME DIRECTIVE (operator, approved) - build-supervisor, Phase 7 Codex cycle 1

What failed: Codex cycle 1 (HEAD 4e6fabc) found 2 P1 and 3 P2 in lib/operator.sh and lib/supervisor.sh (full text: handoff/codex-review-build-supervisor.md).

Apply the fixes as proposed in handoff/failure-report-build-supervisor-codex.md:
1. P1, worktree pruned before merge (lib/operator.sh op_gate PASS branch): remove the `_prune_worktree` call that runs before `gh pr merge`.
   - Worktree builds: merge with `gh pr merge <n> --squash` (no --delete-branch). Only after the merge succeeds: prune the worktree, then `git -C <repo_root> push origin --delete <branch>`, then `git -C <repo_root> branch -D <branch>`.
   - Non-worktree builds: keep `--squash --delete-branch`.
   - If the merge fails, remove nothing. The escalation must log into the intact worktree.
2. P1, fail-open CI wait (lib/operator.sh `_wait_checks_green`): treat the PR JSON as valid only if `.number` is set and `.state == "OPEN"`.
   - Anything else counts as a lookup failure: retry. After 3 consecutive lookup failures, return 1 so the caller escalates.
   - An empty check rollup may count as green only after a valid lookup.
3. P2, Codex closure (lib/operator.sh op_gate): extend the deterministic downgrade so a PASS verdict becomes FAIL unless `codex_closed == true`. Keep the existing unmet-criterion and ci_green checks.
4. P2, failure-report matching (lib/supervisor.sh classify + lib/operator.sh `_newest_failure_report`): factor one shared helper used by both.
   - Match only `failure-report-<feature>.md` and `failure-report-<feature>-<suffix>.md` where <suffix> starts with phase, codex or context.
   - Add the fixture tests/fixtures/states/other-feature-report-running: report `failure-report-demo-next-phase-3.md`, newer than launch, must classify as RUNNING.
5. P2, post-merge log (lib/operator.sh op_post_merge): stop appending the MERGED entry to the repo checkout after cleanup.
   - The "MERGE GATE: PASS" entry stays committed and pushed in the PR before the merge.
   - The MERGED outcome goes only to $WALKAWAY_HOME/logs/operator-<feature>.log, the registry and ntfy.
   - Nothing uncommitted may be written to the default branch or to the next feature's checkout.

Regression tests in tests/test-operator.sh (each must fail on 4e6fabc and pass after the fix):
- PASS verdict with codex_closed:false -> FAIL/rejection directive, gh pr merge NOT called.
- gh pr view failing during `_wait_checks_green` -> escalate, no merge.
- Worktree build where `gh pr merge` fails -> worktree still a valid git worktree (git -C <wt> rev-parse succeeds), branch not deleted, escalation logged inside it.
- Worktree build where the merge succeeds -> merge is called without --delete-branch, the worktree is pruned after the merge, and the remote and local branch are deleted.
- After a merge, `git status --porcelain` in the repo checkout is empty (no uncommitted operator-log change).
- The new states fixture is included in tests/test-states.sh.

Re-run every gate:
- `shellcheck -S warning` on all scripts: must be 0.
- tests parse, states (now 13/13) and operator: all green.
- Commit with a Phase 7 fix message and append a build-log line.

Then run Codex cycle 2 (`codex review --base main`). It is the FINAL cycle (cap 2):
- Record it in handoff/codex-review-build-supervisor.md.
- Fix any P2s in scope, with tests.
- If cycle 2 returns any P1, STOP and write a new failure report. Do not start cycle 3.

Then continue the plan from the build log: Phase 8, open the PR, wait for CI, write the build report LAST. Do not redo committed phases 0-6. Never merge.
