# Phase 1 report - build-supervisor (registry + status)

- New `lib/registry.sh`: `registry_register/get/update/list/status`, `pid_alive` (PID + recorded start-time guard against PID reuse), atomic tmp+mv writes, all under `$WALKAWAY_HOME` (default ~/.walkaway-cli).
- Registry entry `~/.walkaway-cli/registry/<feature>.json`: feature, repo, repo_root, plan, branch, builder_pid, builder_started, watcher_pid, launched_at/launched_epoch, launch_log, resume_count, gate_rejections, approvals, launch_count, queue_next, state, state_since, last_action, operator_pid. Counters survive relaunches (caps hold).
- `walkaway.sh`: registers right before exec (builder PID = `$$`, since cc_launch execs the builder in-process; watcher PID = the PID watcher_start spawned). No name matching. `walkaway status` subcommand prints one table (feature, repo, state, age, in-state, last action) + supervisor last tick.
- `--force` now stops a leftover watcher before starting a new one (previously `--force` still died in watcher_start under set -e); supervisor relaunches rely on it.
- `lib/launch-cc.sh`: `WALKAWAY_BUILDER_CMD` (default `claude`) so drills can run a stub builder. Builder invocation otherwise unchanged.
- `lib/watcher.sh`: exposes WATCHER_PID; state/log dirs default under `$WALKAWAY_HOME` (same paths as before by default).
- Verified with a stub builder in a temp repo: registry JSON written with builder PID == exec'd stub PID; status table renders.
- Gates: shellcheck -S warning rc=0; tests/test-parse-plan.sh 7/7.
- Files: lib/registry.sh (new), walkaway.sh, lib/watcher.sh, lib/launch-cc.sh.
