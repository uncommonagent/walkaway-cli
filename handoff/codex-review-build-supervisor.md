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

## Cycle 1 fixes (3f4af2b, approved fix 1)
All 5 cycle-1 findings fixed with regression tests (operator 51/51, states 13/13; the 13 new operator checks + new
fixture fail on 4e6fabc and pass on 3f4af2b). Cycle-1 status: CLOSED.

## Cycle 2 - FINAL (2026-11-12 ~15:55 EST, `codex review --base main`, HEAD 3f4af2b)

The merge flow can accept stale CI results or proceed after failing to publish its gate decision. Post-merge synchronization can also disrupt another active builder sharing the repository.

Full review comments:

- [P1] Verify checks against the newly pushed gate commit — lib/operator.sh:310-312
  After the gate commit is pushed, GitHub can briefly return the previous commit's successful check rollup before checks for the new head are registered. `_wait_checks_green` immediately accepts that response (including an empty rollup), so this path can merge before the gate commit's CI runs. Track the pushed head SHA and wait for checks associated with that head rather than accepting any green response for the open PR.

- [P1] Avoid switching a checkout used by another active builder — lib/operator.sh:465-466
  When a worktree build merges while another build is running in the main checkout of the same repository, `op_post_merge` unconditionally calls `_sync_default`, which checks that checkout out onto the default branch and pulls. The active-build check in `_launch_next` happens afterward and cannot prevent this from switching the running builder's branch underneath it. Check for a builder using the root checkout before synchronizing it, or update only remote refs until that checkout is idle.

- [P2] Abort merging when the gate decision cannot be pushed — lib/operator.sh:361-362
  If the gate push fails because of authentication, connectivity, or a non-fast-forward update, `|| true` discards the failure and the operator proceeds to check and merge the existing remote PR. This can merge without the required committed gate decision in the PR, while the local decision commit is left behind or deleted during worktree cleanup. Treat a failed commit or push as an escalation and do not attempt the merge.

Builder verification: all three confirmed against the code (no head-SHA comparison in `_wait_checks_green`;
`_sync_default` runs before the active-build check in `_launch_next`; `git push ... || true` at the gate push).

Status: OPEN - 2 P1, 1 P2. Codex cap (2 cycles) reached. Build STOPPED per the approved directive ("if cycle 2
returns any P1, STOP and write a new failure report; do not start cycle 3"):
failure-report-build-supervisor-codex-cycle-2.md.

## Cycle 2 fixes (3f4538d, approved fix 2)
Each fix has a regression test in tests/test-operator.sh, run against new tests + new gh-sim. On 3f4af2b lib/ the
suite scored 57/66 (9 FAIL). After the fix (3f4538d) it scores 66/66.

- [P1] Stale checks: the head was not verified after the gate push.
  - Fix: `supervisor_pr_json` now requests `headRefOid`. `_wait_checks_green <sha>` takes the SHA from
    `git rev-parse HEAD` after the push. A lookup counts as valid only with `.number`, `.state == "OPEN"` and
    `.headRefOid == sha`. A head mismatch means pending (never green) until WALKAWAY_MERGE_CHECK_WAIT runs out,
    then the operator escalates with the reason. An empty rollup on the matching head stays pending for
    WALKAWAY_MERGE_EMPTY_CHECKS_GRACE (default 120 s), then counts as green. The rule "3 lookup failures ->
    escalate" is kept.
  - Tests:
    - T12 "gh pr merge called only after the head matched": FAIL on 3f4af2b (it merged on the stale green
      rollup), PASS now.
    - T12b "escalated: head never reached the gate commit" + "gh pr merge NOT called": FAIL/FAIL on 3f4af2b,
      PASS/PASS now.
    - T13 "merge >= 2s after the first empty-rollup view" (grace 2 s): FAIL on 3f4af2b (merged on the first empty
      view), PASS now.
- [P1] Post-merge sync could switch a checkout that an active builder was using.
  - Fix: one shared helper, `_other_active_build <root> <field>`. `_sync_default` calls it with `.repo`. If another
    non-MERGED build works in the root checkout, the sync runs only `git fetch -q origin` and logs
    "default-branch sync deferred: <feature> active in root". There is no checkout and no pull.
  - `_launch_next` calls the same helper with `.repo_root`, which keeps the plan's one-builder-per-repo rule (that
    match is a superset of `.repo`), so the queue stays held.
  - Tests: T14 "root still on the active build's branch at the same HEAD", "no checkout or pull ran in the root
    (HEAD reflog unchanged)" and "sync deferral logged" were FAIL/FAIL/FAIL on 3f4af2b and PASS now. "queue held"
    passes on both.
- [P2] A failed gate push was swallowed.
  - Fix: `_commit_decision` returns the commit status, and the push is checked. If either fails, the operator
    escalates with "Merge gate PASS for <f> could not be pushed (<last line>). Push/merge manually?". It does not
    wait for checks and does not merge.
  - Tests: T15 (an origin pre-receive hook rejects the push) "escalated: PASS could not be pushed" + "gh pr merge
    NOT called" were FAIL/FAIL on 3f4af2b and are PASS now.

Cycle-2 status: CLOSED by regression-test evidence (cap 2, no cycle 3, per operator approval)
