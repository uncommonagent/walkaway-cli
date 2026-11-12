# Failure report - build-supervisor - Phase 7 (Codex cycle 1)

## Phase / gate
Phase 7 (Codex review). Codex cycle 1 (`codex review --base main` at 4e6fabc) returned 2 P1 + 3 P2, all concrete defects
in this diff (full text: handoff/codex-review-build-supervisor.md). Codex P1 is a stop rule; per the protocol the
builder stops with a proposed fix and the supervisor's operator triages. Phases 0-6 are committed and green
(shellcheck -S warning 0; tests parse 7/7, states 12/12, operator 31/31; live drill AC2 PASS; live install AC3 PASS).

## What was attempted
Nothing yet - stop rule, no fixes attempted.

## Proposed fix (all in plan scope: items 2/3, files lib/operator.sh, lib/supervisor.sh, tests/test-operator.sh)
1. P1 worktree pruned before merge (lib/operator.sh op_gate PASS branch): remove the `_prune_worktree` call that runs
   before `gh pr merge`. For worktree builds merge with `gh pr merge <n> --squash` (no `--delete-branch`, which fails
   while the branch is checked out in the worktree), and only after a successful merge: prune the worktree, then
   `git -C <repo_root> push origin --delete <branch>` and `git branch -D <branch>`. Non-worktree builds keep
   `--squash --delete-branch`. On merge failure nothing is removed, so escalation logs into the intact worktree.
2. P1 fail-open CI wait (lib/operator.sh `_wait_checks_green`): treat the PR JSON as valid only if `.number` is set
   and `.state == "OPEN"`; otherwise count a lookup failure and retry, and after 3 consecutive lookup failures return 1
   (the caller already escalates). Only then may an empty rollup count as green.
3. P2 Codex closure (lib/operator.sh op_gate): extend the deterministic downgrade so verdict PASS becomes FAIL unless
   `codex_closed == true` (in addition to the existing unmet-criterion and `ci_green` checks).
4. P2 failure-report matching (lib/supervisor.sh classify + lib/operator.sh `_newest_failure_report`): match only
   `failure-report-<feature>.md` and `failure-report-<feature>-<suffix>.md` where `<suffix>` starts with `phase`,
   `codex` or `context` (the documented names), so `demo` never consumes `failure-report-demo-next-phase-3.md`.
   Factor one shared helper used by both. Add a fixture `tests/fixtures/states/other-feature-report-running`
   (report `failure-report-demo-next-phase-3.md` newer than launch -> RUNNING).
5. P2 post-merge log (lib/operator.sh op_post_merge): stop appending the MERGED entry to the repo checkout after
   cleanup. The "MERGE GATE: PASS" entry is already committed and pushed into the PR before the merge; the MERGED
   outcome goes to `$WALKAWAY_HOME/logs/operator-<feature>.log` + registry + ntfy only. No uncommitted write to the
   default branch or the next feature's branch.
Regression tests in tests/test-operator.sh: PASS with `codex_closed:false` -> FAIL/rejection (no merge); gh lookup
failing during `_wait_checks_green` -> escalate, no merge; after a merge the repo has no uncommitted operator-log change.
Then re-run all gates, Codex cycle 2 (final cycle, cap 2), open the PR, wait for CI, write the build report LAST.

## Recommendation
Approve the five fixes as proposed plus the regression tests, then continue from the build log with Phase 7
(Codex cycle 2). No PROTECTED action involved.

## Notes
- The live supervisor (installed in Phase 6) has adopted this build, so this report is also the first real triage
  by the operator.
- Watcher 11041 was started before the supervisor existed and runs the old (unsuppressed) code, so this stop may
  ping twice (watcher + supervisor). Expected once; new watchers are suppressed.
