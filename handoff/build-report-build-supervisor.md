# Build Report: build-supervisor

Build started: 2026-11-12 14:23 ET (plan b68ca61; Phase 0 at 14:26)
Build ended: 2026-11-12 16:11 ET
Status: COMPLETE

## TL;DR
The build supervisor is built and live on the Mini.
- It keeps a registry of every walkaway build. Builder and watcher PIDs come from the launch, never from name
  matching.
- `walkaway status` prints one table from that registry.
- A launchd supervisor ticks every 2 min, classifies each build into one of 7 states, and sends one ntfy per state
  change.
- A `claude -p` operator handles DIED/STALLED (auto-resume), STOPPED (triage: approve + relaunch, or escalate one
  question) and DONE (merge gate, then squash-merge, then launch the next queued plan). PROTECTED actions always
  escalate.

It has run against this build for real:
- It adopted this build's running builder.
- It triaged both Codex stops itself, approving fix 1 and fix 2 and relaunching each time, with one real-topic ntfy
  per transition.

Codex: two cycles, 4 P1 + 4 P2 in total, all fixed with regression tests that fail on the pre-fix code. Both cycles
are CLOSED.

PR #1 is open and CLEAN. The repo has no CI.

Next: the supervisor's merge gate will pick this up as DONE and merge it. If Jim would rather review first, he can
read PR #1 and push bpo-comp-tool's protocol commit 82d2446 (see "What Jim should do next").

## Phases executed
- Phase 0, prepare: 9336d8b. Baseline: shellcheck 0, parse 7/7. The 7 plan items were mapped to phases.
- Phase 1, registry + `walkaway status`: a583e98. shellcheck 0, parse 7/7.
- Phase 2, supervisor states + transition ntfy + heartbeat + lock: b2543f5. shellcheck 0, parse 7/7.
- Phase 3, operator + PROTECTED guard + merge gate + queue: 7942f50. shellcheck 0, parse 7/7.
- Phase 4, launchd installer + adoption + watcher suppression: 493d0ba, then f236b85 (SC2045 gate fix).
  shellcheck 0.
- Phase 5, tests: aa57789. states 12/12, operator 28/28. Fixed a relaunch pipe hang and a protected_hit jq bug.
- Phase 6, smoke: 716422f (drill fixes: AbandonProcessGroup, multi-line directives) and 4e6fabc. Live drill a-e
  PASS, live install + adoption, status archived, protocol commit.
- Phase 7, Codex:
  - Cycle 1 stopped at 421216c. The operator approved fix 1 (3c06829). Fixes landed in 3f4af2b: operator 51/51,
    states 13/13.
  - Cycle 2 stopped at 41e7e41. The operator approved fix 2 (afd472f). Fixes landed in 3f4538d: operator 66/66.
    Closure was recorded in c6e97c4.
- Phase 8, PR + CI: 4c2c241 (evidence manifest), 06d03a2 (PR #1, CI resolved).
- Final gates: `shellcheck -S warning` 0, both combined and per file. parse 7/7, states 13/13, operator 66/66.

## Files changed
Overall: 120+ files against main. Most of them are archived evidence and test fixtures.
- **P1:** walkaway.sh (+27), lib/registry.sh (+147), lib/launch-cc.sh, lib/watcher.sh.
- **P2:** lib/supervisor.sh (+274), lib/notify.sh (+20).
- **P3:** lib/operator.sh (+453), templates/operator-prompt.md (+72), lib/registry.sh, walkaway.sh.
- **P4:** install-supervisor.sh (+62), lib/adopt.sh (+69), lib/watcher.sh, README.md (+36).
- **P5:** tests/test-supervisor-states.sh (+92), tests/test-operator.sh (+154), tests/drill/{gh-sim,scratch,stub-builder}.sh,
  tests/fixtures/states/* (12 fixtures), install-supervisor.sh, lib/operator.sh, lib/supervisor.sh.
- **P6:** tests/drill/run-drill.sh (+145), lib/operator.sh, lib/supervisor.sh, install-supervisor.sh,
  templates/operator-prompt.md, .gitignore, tests/*; evidence in handoff/drill-evidence-build-supervisor/ and
  handoff/live-install-evidence-build-supervisor/.
- **P7 fix 1:** lib/operator.sh, lib/supervisor.sh, tests/test-operator.sh (+89), tests/drill/gh-sim.sh, README.md, plus
  the fixture other-feature-report-running.
- **P7 fix 2:** lib/operator.sh (now 532 lines), lib/supervisor.sh, tests/drill/gh-sim.sh (now 92 lines),
  tests/test-operator.sh (now 304 lines), ROADMAP.md (new).
- **P8:** handoff/build-supervisor-evidence/MANIFEST.md and the handoff reports.

## Migrations applied
None. This is a bash CLI with no database.

## Tests added
- tests/test-supervisor-states.sh: 13 fixtures. That covers all 7 states plus edge cases: a recycled PID, CI failed
  after the report, CI pending, a stale build report, a stale failure report, and another feature's report.
- tests/test-operator.sh: 66 checks over 16 scenarios in a real scratch world: real walkaway launches, stub
  builders, gh-sim, and a stubbed claude. Scenarios:
  - resume cap
  - triage approve and protected
  - gate FAIL/PASS + queue
  - PASS without Codex closure
  - CI lookup fails closed
  - worktree merge fail/success
  - stale head
  - head never matches
  - empty-rollup grace
  - active root builder
  - gate push rejected
  - status
- tests/drill/run-drill.sh: the AC2 live drill harness, with a real launchd agent, real `claude -p` and real ntfy.

## Codex review summary
- **Cycle 1 (4e6fabc): 2 P1 + 3 P2.**
  - Worktree pruned before the merge.
  - Fail-open CI wait.
  - PASS without Codex closure.
  - Substring failure-report match.
  - MERGED log left uncommitted.
  - All fixed in 3f4af2b. 13 checks + 1 fixture fail on 4e6fabc and pass after.
- **Cycle 2 (3f4af2b, final): 2 P1 + 1 P2.**
  - Stale-head green.
  - Post-merge sync switching an active root builder's checkout.
  - Swallowed gate push failure.
  - All fixed in 3f4538d. Tests T12/T12b/T13/T14/T15: 9 checks FAIL on 3f4af2b lib/ (57/66), 66/66 now.
- Status: both cycles CLOSED. The cap of 2 was reached, there was no cycle 3, and closure is by regression-test
  evidence per operator approval fix 2. Details: handoff/codex-review-build-supervisor.md.

## Smoke test results
Real-system evidence. Index: handoff/build-supervisor-evidence/MANIFEST.md.
- **AC2 live drill**, 15:24-15:30 ET: real launchd agent, real `claude -p`, and real ntfy on the drill topic.
  - (a) DIED -> auto-resume 121 s after the kill.
  - (b) operator APPROVE -> relaunch.
  - (c) PROTECTED (live "Best of Kitchen" publish) -> ESCALATED at priority 4 with no relaunch.
  - (d) bad evidence -> gate FAIL: row 7 99.99 vs 52.25 -> rejection directive.
  - (e) good evidence -> squash-merged, and queued drill-e2 launched.
  - ntfy: 12 polled == 12 sent.
- **AC3 live install**: the agent was installed at 15:33 ET and adopted builder 11000. Real topic: tXJ25yUdpEDJ.
- **Live operator loop 1:** STOPPED m0v4XW0QmKvH (20:37:33Z) -> RUNNING "approved fix 1" wG7gBav1iEom (20:39:34Z).
- **Live operator loop 2:** STOPPED qYnjYxwCULHR (20:51:38Z) -> RUNNING "approved fix 2" R11YwSNratD3 (20:53:39Z).
  5 local sends == 5 supervisor messages on the real topic. Registry: approvals 2, launch_count 3.
- **Live GitHub, PR #1:** `headRefOid` 4c2c241 == local HEAD. The new CI-wait verdict is `empty` for HEAD and
  `stale` for HEAD~1.
- **AC4:** `walkaway status` output is archived from live runs 1-2 and from the drill.

## Known issues / deferred
- **AC5 protocol commit is unpushed.** bpo-comp-tool `main` holds 82d2446, which is 1 ahead of origin. Pushing
  another repo's main was not authorized for this build.
- **ROADMAP follow-ups, not built:**
  - The lib/watcher.sh:74 substring glob.
  - Feature-name prefix ambiguity (`bpo-j`).
  - The protocol report-name doc (~line 457).
  - The relaunch-label ntfy race (cosmetic).
- **The AC2 drill was not re-run after fix 2.** fix 2 changed gh-sim's merge implementation (merge in a temp clone
  instead of checking out main in the root). T6 and T11 cover both merge forms the drill uses, and both pass.
  Re-running would rewrite the committed Phase 6 evidence and make extra live `claude -p` and ntfy calls.
- **Empty-rollup grace.** This repo has no CI, so the merge gate waits WALKAWAY_MERGE_EMPTY_CHECKS_GRACE (120 s) on
  the empty rollup before merging. That is by design.
- **Root-checkout sync.** The supervisor runs from this checkout. After this PR merges, the post-merge sync puts it
  on the updated main, which is required for the supervisor to keep running the merged code.

## Branch / PR
Branch feature/build-supervisor. PR: https://github.com/uncommonagent/walkaway-cli/pull/1. It is ready for the
merge gate. Not merged by the builder.

## CI result
No CI is configured: 0 workflows, 0 check runs, 0 statuses, and `gh pr checks 1` reports "no checks reported".
mergeStateStatus is CLEAN and mergeable is MERGEABLE at head 06d03a2 (before this report commit).

## What Jim should do next
1. Nothing is required for the merge. The supervisor classifies this build as DONE and its gate merges PR #1. If you
   want to look first, read PR #1 and the MANIFEST.
2. Decide whether to push bpo-comp-tool `main` (82d2446, the AC5 protocol update).
3. Optional: schedule the ROADMAP follow-ups as a small build.
