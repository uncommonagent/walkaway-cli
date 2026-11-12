# Codex review - build-supervisor

## Cycle 1 (2026-11-12 15:35 EST, `codex review --base main`, HEAD 4e6fabc)

The operator can bypass required merge checks and destroys worktree state before confirming merge success. Failure-report matching and post-merge logging also introduce incorrect behavior in supported build flows.

Full review comments:

- [P1] Preserve the worktree until the merge succeeds — /Users/jimross/Projects/walkaway-cli/lib/operator.sh:356-360
  For worktree builds, this removes the build checkout before `gh pr merge` succeeds. If merging fails because of conflicts, permissions, or connectivity, escalation then writes into the deleted checkout path, recreating a plain directory where the Git worktree used to be. This loses untracked build artifacts and prevents a clean resume. Remove the worktree only after confirming the merge, and retain a valid repository location for subsequent logging.

- [P1] Fail closed when the post-push PR lookup fails — /Users/jimross/Projects/walkaway-cli/lib/operator.sh:295-296
  If `gh pr view` fails during this check, `supervisor_pr_json` returns `{}`, which `supervisor_checks` interprets as green because the check list is empty. The operator consequently proceeds to merge without verifying CI after its gate commit. Require a successful lookup of an open PR before treating an empty check list as green; lookup failures should retry or escalate.

- [P2] Enforce Codex closure before accepting a PASS verdict — /Users/jimross/Projects/walkaway-cli/lib/operator.sh:335-335
  A decision containing `verdict: "PASS"`, met criteria, and `ci_green: true` still merges when `codex_closed` is false. The schema explicitly collects this flag and the operator prompt requires closure for PASS, but this deterministic validation omits it. Reject or escalate such contradictory decisions rather than merging with an explicitly unfinished review.

- [P2] Match failure reports to the exact feature — /Users/jimross/Projects/walkaway-cli/lib/supervisor.sh:106-106
  The substring glob also matches other features: a build named `demo` consumes `failure-report-demo-next-phase-3.md`. If that report is newer than this build's launch, a healthy builder is classified STOPPED and triaged using another feature's failure. Match the feature at the documented filename boundaries and apply the same correction to `_newest_failure_report`.

- [P2] Persist the merge decision before switching or deleting checkouts — /Users/jimross/Projects/walkaway-cli/lib/operator.sh:446-450
  The MERGED log entry is appended after checkout synchronization and queue launch, and is never committed. For ordinary builds this leaves an operator modification on main or the next feature branch; for worktree builds `_oplog` recreates the already-removed checkout directory just to hold the log. Record and commit the merge decision in a surviving repository before cleanup or launching the next builder.

Status: OPEN - 2 P1, 3 P2. Build stopped per protocol (Codex P1 = stop rule; routed to the supervisor operator via failure-report-build-supervisor-codex.md).
