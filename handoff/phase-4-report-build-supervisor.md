# Phase 4 report - build-supervisor (launchd agent + adoption)

- New `install-supervisor.sh`: renders `~/Library/LaunchAgents/com.jimross.walkaway-supervisor.plist` (StartInterval 120, RunAtLoad, PATH incl. /opt/homebrew/bin + ~/.local/bin, log ~/.walkaway-cli/logs/supervisor.log), `plutil -lint`, runs adoption, touches `supervisor.enabled`, `launchctl bootstrap/enable gui/<uid>`. `--uninstall` boots it out and removes the marker. The agent runs `lib/supervisor.sh tick` from this repo's working tree (same as the `walkaway` symlink).
- New `lib/adopt.sh`: registry backfill from `/tmp/walkaway-*.log` (newest first): plan/feature/branch/repo/watcher PID from the log, builder PID = PPID of the logged watcher (walkaway execs the builder; the watcher is its child). The logged PID's command line is checked to still be that feature's watcher; launched_at = builder process start time. Already-registered live builds are skipped.
- `lib/watcher.sh`: while `supervisor.enabled` exists, watchers log "suppressed (supervisor active)" instead of pinging (keeps one ntfy per transition). Watchers already running hold the old code until they exit.
- `supervisor.sh adopt` delegates to adopt.sh. README: status, supervisor, operator table, queue, new env vars + paths.
- Sandbox adoption test (scratch WALKAWAY_HOME, real launch logs): adopted build-supervisor (builder 11000 / watcher 11041) and review-page-v4 (builder 6665 / watcher 6695, from walkaway-review-page-v4-3.log); 7 dead/duplicate logs skipped; both classify RUNNING.
- Gates: shellcheck -S warning rc=0 (incl. install-supervisor.sh) after fix attempt 1 (SC2045 in adopt.sh slipped into commit 493d0ba because the commit chain did not depend on shellcheck; fixed in the follow-up commit); parse tests 7/7.
- Files: install-supervisor.sh (new), lib/adopt.sh (new), lib/watcher.sh, README.md.
- Live install is deferred to Phase 6 (AC3) after tests and the drill.
