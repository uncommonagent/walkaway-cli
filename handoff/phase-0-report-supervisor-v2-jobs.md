# Phase 0 report - supervisor-v2-jobs (prepare)

- Read: WALKAWAY_BUILD_PROTOCOL.md (bpo-comp-tool), build-plan-supervisor-v2-jobs.md, README.md, ROADMAP.md. This repo has no CLAUDE.md or TOOLCHAIN_OVERVIEW.md. Branch `feature/supervisor-v2-jobs` was clean at d3d5af9. Host: the Mini.
- **No phase list, "Phase gates" or files budget in the plan.** Its 5 build items map onto the protocol's canonical phases:
  - P1 DIED/DONE fix + AC1 regression (item 1)
  - P2 jobs.yaml + read-only check engine + dump (item 2, AC2 code)
  - P3 job day-state machine + ntfy + heartbeat + supervisor tick + `walkaway status` JOBS table (items 3, 5)
  - P4 job operator: diagnose, incident, template-v2 fix plan, queue/launch or ESCALATE, post-fix retry + confirm (item 4)
  - P5 tests (AC3 fixtures, AC5 suite)
  - P6 smoke: AC2 live dump, AC3 drill on the drill ntfy topic, AC4 live enable + status archive
  - P7 Codex (cap 2) + evidence MANIFEST + PR + CI + build report LAST
- Gates (bash adaptation, same as build-supervisor):
  - `shellcheck -S warning` on every script = 0
  - every `tests/test-*.sh` green
  - git clean after the phase commit
  - phase report + build-log line
  - Baseline: shellcheck 0, parse 7/7, states 13/13, operator 66/66.
- **Live-safety constraint found:** launchd `com.jimross.walkaway-supervisor` runs `lib/supervisor.sh` from THIS working tree every 120 s, and it supervises this build (builder pid 146) plus bf-taste-scoring (pid 764).
  - Every edit to lib/ is live on the next tick.
  - So lib changes are written and tested in a scratch copy first, then landed whole.
  - Job watching is gated on `~/.walkaway-cli/jobs.enabled` and stays off until Phase 6.
- Jobs: discovered and confirmed against real rows (handoff/supervisor-v2-jobs-evidence/phase0-job-discovery.md). Deviations from the plan's times are each backed by a real row:
  - cc-optin-am: by 15:45 (11/05 DONE 13:26 ET).
  - cc-optin-pm: disabled (PM off since 10/31, `pmSessionEnabled = false`).
  - showingtime: FAILED only after its 12:30 retry.
  - realtea-generate: by 09:15 (11/09 generated 08:31 ET).
  - realtea-publish: by 10:15.
- **BF daily has no run-now path** (plan item 4 named it as the example). After a fix merges, the job is confirmed by the extension's own 30-min retries or by the next run. Only showingtime has a safe automatic retry (its URL trigger). The others' retries are PROTECTED or need a browser session.
- Every check needs the service-role key from the owner repo's `.env.local`. The key is read at check time and never logged; the anon key returns `[]`.
- 11/13 DIED root cause (operator-log-bf-deals-ingest-fix.md + git log), in order:
  1. The report was committed 09:28:06 and the builder exited.
  2. At 09:28:47 the report was newer than launch, but the PR checks were not green yet, so classify fell through to liveness and returned DIED.
  3. The relaunch moved `launched_epoch` past the report.
  4. The resumed builder committed "no-op resume" without touching the report, so it read DIED again.
  5. Cap reached, so ESCALATED.
- Tools: shellcheck, jq, gh, codex, claude, and ruby (stdlib YAML → JSON for jobs.yaml). No yq, no pyyaml.
- Next phase entry: none blocked.
