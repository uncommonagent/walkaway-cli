# walkaway-cli roadmap

## Follow-ups

Items that remain after build-supervisor's Codex cycle 2. Under the protocol's 2-cycle cap they are logged here and
were not built. Source: handoff/failure-report-build-supervisor-codex-cycle-2.md (Notes).

- **Watcher substring glob.** lib/watcher.sh:74 still matches `failure-report-*<feature>*`, so it can fire on
  another feature's report. The supervisor and operator already use the exact-feature matcher
  `supervisor_failure_report`. Impact today is low, because watchers are suppressed while the supervisor is
  installed. Fix: reuse that helper in the watcher.
- **Feature-name prefix ambiguity.** A feature named `bpo-j` still matches
  `failure-report-bpo-j-phase-5-5-...-phase-0.md`, which is a real report name from another build. Prefix plus
  suffix matching cannot tell the two apart. Fix: put a separator or the full feature id in report names, or
  record the report path in the registry.
- **Protocol report-name doc.** WALKAWAY_BUILD_PROTOCOL.md (~line 457) documents
  `failure-report-<feature>-<phase>.md`. A bare-number suffix such as `-3` would not match the supervisor's
  `-phase*/-codex*/-context*` rule. Every real report seen so far uses `-phase-N` or `-codex`. Fix: make the doc
  say `-phase-N`, or widen the matcher.
- **Relaunch-label ntfy race.** `registry_register` sets `operator_pid` to null on relaunch before the operator
  records its action. As a result, the first RUNNING ntfy after a relaunch can miss the "approved fix N" label.
  This is cosmetic. Fix: have the operator write last_action before it relaunches, or have the supervisor wait for
  it.

### From supervisor-v2-jobs (Codex cycle 2, 2026-11-13)

- **Stale queue-lock takeover race.** `queue_lock` in lib/registry.sh takes over a stale lock (its pid is dead) by
  renaming it aside. Suppose two waiters both see the same dead pid. The first renames the stale lock and makes a
  fresh one before the second runs `mv`. The second then renames away the first waiter's live lock, and both enter
  the launch critical section. This needs a lock holder killed with SIGKILL (or a crash) mid-launch while two other
  launchers for the same repo are waiting. Normal exits release the lock through the EXIT trap. Fix: serialize
  reclamation (a separate reclaim lock), or verify that the renamed directory's pid is the dead pid that was
  inspected and restore it otherwise. Source: handoff/codex-review-supervisor-v2-jobs.md cycle 2.
- **Heartbeat hours default.** lib/supervisor.sh reads `${WALKAWAY_HEARTBEAT_HOURS:-09 13 17}`, so an empty value
  means the default hours, not "off". Tests now use `off`. Consider `${WALKAWAY_HEARTBEAT_HOURS-...}` so that
  empty disables it.
