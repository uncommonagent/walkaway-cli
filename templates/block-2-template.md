You are executing a walkaway build per ${WALKAWAY_PROTOCOL_PATH} (adapted - check the build plan's Phase gates section for any project-specific overrides, e.g. a bash CLI uses shellcheck instead of pnpm tsc).

Read these in order before touching code:
1. ${WALKAWAY_PROTOCOL_PATH} (operating rules)
2. ${BUILD_PLAN_PATH} (the plan — this is the contract)
3. CLAUDE.md, TOOLCHAIN_OVERVIEW.md, and any other top-level docs in ${REPO_PATH} for project conventions

Context: You are on branch ${BRANCH_NAME}. Execute all phases listed in the build plan. Each phase ends with the mandatory gates per WALKAWAY_BUILD_PROTOCOL.md. Commit after each successful phase.

Phase 6 (smoke) is MANDATORY and must produce real-system evidence (row counts, API response excerpts, or live IDs/timestamps) — not just documentation about a smoke test. Phase 7 (final report) is MANDATORY.

Stop rules from the plan apply. Do NOT build anything in the plan's "Do NOT build" section.

Write phase reports to handoff/phase-N-report-${FEATURE_NAME}.md after each phase. Append one-liners to handoff/build-log-${FEATURE_NAME}.md.

Print when done: every file modified per phase, all gate results, smoke results with real evidence, and anything deferred or flagged as follow-up.
