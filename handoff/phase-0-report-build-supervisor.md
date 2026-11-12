# Phase 0 report - build-supervisor (prepare)

- Read: WALKAWAY_BUILD_PROTOCOL.md (bpo-comp-tool), build-plan-build-supervisor.md, README.md. No CLAUDE.md / TOOLCHAIN_OVERVIEW.md in this repo.
- Branch `feature/build-supervisor` clean at b68ca61. Host is Jims-Mac-Mini (the Mini) - launchd install target is this machine.
- The plan has no explicit phase list or "Phase gates" section, so phases are mapped from its 7 items onto the protocol's canonical structure:
  P1 registry + launch integration + `walkaway status` (items 1, 7) / P2 supervisor state machine + ntfy + heartbeat + lock (item 2) /
  P3 operator + PROTECTED guard + queue + merge gate (items 3, 4, 5) / P4 launchd agent + adoption backfill (AC3 code) /
  P5 fixture tests for the 7 states (AC1) / P6 smoke: live drill (AC2), live install + adoption (AC3), status archive (AC4), protocol doc (AC5) /
  P7 Codex review + PR + CI + final report.
- Gates (bash CLI adaptation): `shellcheck -S warning` on all scripts = 0 findings (baseline: 0 at warning; 6 pre-existing SC2153 infos tolerated), all `tests/test-*.sh` pass, git clean after commit.
- Baseline: shellcheck -S warning rc=0; tests/test-parse-plan.sh 7/7.
- Tools: shellcheck, gh, claude 2.1.309 (supports -p, --json-schema, --append-system-prompt-file), codex, jq. No bats, no flock, no timeout -> plain bash tests, mkdir lock, bash poll loops.
- Live builds at start: review-page-v4 (builder 6665 / watcher 6695, audrey-ops-platform, PR #26 open, directive 2 in flight) and build-supervisor (this session, builder 11000 / watcher 11041). Builder PID = PPID of the watcher PID (cc_launch execs claude in the walkaway process) - this is the launch-lineage backfill rule, no name matching.
- Resume-directive convention (from audrey-ops plans): `## RESUME DIRECTIVE N (date ET) - read first` inserted under the plan title; done ones marked `[DONE]`. The operator follows it.
- "Protocol doc in ops": no WALKAWAY_BUILD_PROTOCOL.md exists in ~/Projects/ops; the canonical copy every launch reads is ~/Projects/BPO/bpo-comp-tool/handoff/WALKAWAY_BUILD_PROTOCOL.md (protocol edits are committed on its main historically). AC5 will update that file. Flagged for Jim.
- Next phase entry: none blocked.
