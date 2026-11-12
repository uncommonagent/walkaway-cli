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
