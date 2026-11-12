# Evidence manifest - build-supervisor

This file maps each plan acceptance criterion to the archived files that prove it (protocol "Merge-gate acceptance
standard" rule 1). All paths are relative to the repo root. Evidence is in three places:
- `handoff/drill-evidence-build-supervisor/` (D): the AC2 drill.
- `handoff/live-install-evidence-build-supervisor/` (L): the live Mini.
- the test suites.

Source of truth (rule 8):
- AC1 and the operator tests: the fixture directories and the test assertions.
- AC2: the ntfy JSON poll API (`https://ntfy.sh/<topic>/json?poll=1`) plus each scratch repo's registry, plan and
  bare origin.
- AC3 and AC4: launchd (`launchctl print`), `~/.walkaway-cli/registry/`, and the real topic
  `jim-throughline-9k2x7q-builds`.

## AC1 - unit tests: state classification for each of the 7 states
- `tests/test-supervisor-states.sh` reads the fixtures in `tests/fixtures/states/*/` (13 fixtures). It covers
  RUNNING, STALLED, STOPPED, DIED, DONE, MERGED and ESCALATED (fixtures `running`, `stalled`, `stopped`, `died`,
  `done`, `merged`, `escalated`), plus 6 edge fixtures: `recycled-pid-died`, `report-ci-failed-stopped`,
  `report-ci-pending-died`, `stale-build-report-running`, `stale-failure-report-running`,
  `other-feature-report-running`. Result at the final commit: **13/13**.
- `tests/test-operator.sh` tests the operator actions for each state (resume cap, triage approve/protected,
  gate FAIL/PASS/queue, Codex closure, fail-closed CI wait, worktree merge fail/success, stale head, empty-rollup
  grace, active root builder, gate push rejected). Result: **66/66**.
- `tests/test-parse-plan.sh`: **7/7**.
- The commands and results are recorded in `handoff/build-log-build-supervisor.md`, in the last Phase 7 lines.

## AC2 - live drill (a)-(e), one ntfy per transition
- Summary table and polled ntfy list: `handoff/smoke-results-build-supervisor.md` ("AC2 live drill").
- Timeline with real timestamps: D `timeline.md`. Scenario (a) has the kill at 15:26:06 and the new builder
  121 s later.
- ntfy, 12 polled == 12 local, 1:1: D `ntfy-poll.json`, D `ntfy-poll-messages.tsv`, D `ntfy-local.log`.
- (a) DIED + auto-resume: D `launches/launches-drill-a`, D `plans/build-plan-drill-a.md` (directive "resume 1/2"),
  D `registry/drill-a.json`.
- (b) approve + relaunch: D `plans/build-plan-drill-b.md`, D `operator-logs/operator-log-drill-b.md`,
  D `registry/drill-b.json` (approvals 1, launch_count 2).
- (c) PROTECTED -> ESCALATED, no relaunch: D `ntfy-poll-messages.tsv` (priority 4), D `registry/drill-c.json`
  (launch_count 1), D `operator-logs/operator-log-drill-c.md`.
- (d) bad evidence -> rejection directive: D `gate-drill-d.md`, D `plans/build-plan-drill-d.md`,
  D `operator-logs/operator-log-drill-d.md`.
- (e) good evidence -> merged + queued plan launched: D `gate-drill-e.md`, D `drill-re-origin-main.log` (squash
  commit on origin main), D `registry/drill-e2.json`, D `launches/launches-drill-e2`, D `gh-sim-calls.log`.
- Supervisor and operator logs: D `supervisor.log`, D `operator-jobs.log`.

## AC3 - launchd agent on the Mini + adoption of live builds
- Agent: L `com.jimross.walkaway-supervisor.plist`, L `launchctl-print.txt` (run interval 120 s, runatload,
  abandon process group).
- Adoption from the launch logs: L `supervisor.log`, L `registry-build-supervisor.json` (adopted builder 11000,
  watcher 11041), L `ntfy-poll-real-topic.jsonl` (tXJ25yUdpEDJ 20:33:32Z RUNNING).
- The supervisor in production, supervising this build through two real STOPPED -> approve -> relaunch loops:
  - Loop 1: L `live-triage-2026-11-12/` (m0v4XW0QmKvH STOPPED 20:37:33Z -> wG7gBav1iEom RUNNING "approved fix 1"
    20:39:34Z).
  - Loop 2: L `live-triage-2-2026-11-12/` (qYnjYxwCULHR STOPPED 20:51:38Z -> R11YwSNratD3 RUNNING "approved fix 2"
    20:53:39Z). Its 5 local sends match the 5 supervisor messages on the real topic 1:1. Registry: approvals 2,
    launch_count 3.
  - Operator commits on this branch: 3c06829 and afd472f. The operator log is
    `handoff/operator-log-build-supervisor.md`.

## AC4 - `walkaway status` output archived
- Live: L `walkaway-status.txt`, L `live-triage-2026-11-12/walkaway-status.txt`,
  L `live-triage-2-2026-11-12/walkaway-status.txt`.
- Drill (6 builds across the states): D `walkaway-status.txt`.

## AC5 - protocol doc updated and committed
- `~/Projects/BPO/bpo-comp-tool/handoff/WALKAWAY_BUILD_PROTOCOL.md`, commit `82d2446` on bpo-comp-tool `main`. It
  adds `walkaway status` in place of name-matched ps, the operator owning resume/triage/merge gate, Codex P1 routed
  to the operator, and the Codex cap kept at 2.
- No WALKAWAY_BUILD_PROTOCOL.md exists in `~/Projects/ops`. This is the canonical copy every launch reads (flagged
  in phase-0-report).
- The commit is local: bpo-comp-tool `main` is 1 commit ahead of origin. Pushing it is Jim's call.

## Codex closure (gate input)
- `handoff/codex-review-build-supervisor.md`:
  - Cycle 1: CLOSED (3f4af2b).
  - Cycle 2: CLOSED by regression-test evidence (3f4538d, cap 2, no cycle 3, per operator approval fix 2).
- The fail-on-old / pass-on-new record for both cycles' regression tests is in
  `handoff/phase-7-report-build-supervisor.md` and `handoff/build-log-build-supervisor.md`.
