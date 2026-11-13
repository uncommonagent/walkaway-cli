#!/usr/bin/env bash
# Installs (or removes) the walkaway supervisor launchd agent: com.jimross.walkaway-supervisor, every 2 min.
#
#   ./install-supervisor.sh              install + load, adopt running builds, first tick
#   ./install-supervisor.sh --uninstall  unload + remove (watchers resume their own ntfy pings)
#   ./install-supervisor.sh --jobs-on    start watching the scheduled jobs in jobs.yaml (--jobs-off stops)
#
# Drills: WALKAWAY_SUPERVISOR_LABEL, WALKAWAY_HOME, WALKAWAY_LAUNCH_LOG_GLOB and WALKAWAY_EXTRA_ENV_XML
# (<key>/<string> pairs for the agent's environment) point a second agent at a scratch world.
#
# While installed, ~/.walkaway-cli/supervisor.enabled exists and watchers stop sending their own pings:
# the supervisor sends exactly one ntfy per state change instead.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="${WALKAWAY_SUPERVISOR_LABEL:-com.jimross.walkaway-supervisor}"
WALKAWAY_HOME="${WALKAWAY_HOME:-$HOME/.walkaway-cli}"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
DOMAIN="gui/$(id -u)"

# Job watching (jobs.yaml) is a flag file the running supervisor reads every tick: no reinstall needed.
if [[ "${1:-}" == "--jobs-on" ]]; then
  mkdir -p "$WALKAWAY_HOME"; touch "${WALKAWAY_HOME}/jobs.enabled"
  echo "Job watching ON (${WALKAWAY_HOME}/jobs.enabled); next supervisor tick checks jobs.yaml."
  exit 0
fi
if [[ "${1:-}" == "--jobs-off" ]]; then
  rm -f "${WALKAWAY_HOME}/jobs.enabled"
  echo "Job watching OFF."
  exit 0
fi

if [[ "${1:-}" == "--uninstall" ]]; then
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$PLIST" "${WALKAWAY_HOME}/supervisor.enabled" "${WALKAWAY_HOME}/jobs.enabled"
  echo "Supervisor unloaded and removed."
  exit 0
fi

mkdir -p "${WALKAWAY_HOME}/logs" "${WALKAWAY_HOME}/registry" "${WALKAWAY_HOME}/queue" "${WALKAWAY_HOME}/state" "$(dirname "$PLIST")"
chmod +x "${SCRIPT_DIR}/lib/"*.sh

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${SCRIPT_DIR}/lib/supervisor.sh</string>
    <string>tick</string>
  </array>
  <key>StartInterval</key><integer>120</integer>
  <key>RunAtLoad</key><true/>
  <!-- Relaunched builders and detached operator jobs must outlive the tick: by default launchd kills the
       job's whole process group when the tick exits (nohup does not protect against that). -->
  <key>AbandonProcessGroup</key><true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:${HOME}/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>WALKAWAY_HOME</key><string>${WALKAWAY_HOME}</string>
${WALKAWAY_EXTRA_ENV_XML:-}  </dict>
  <key>StandardOutPath</key><string>${WALKAWAY_HOME}/logs/supervisor.log</string>
  <key>StandardErrorPath</key><string>${WALKAWAY_HOME}/logs/supervisor.log</string>
</dict>
</plist>
EOF
plutil -lint "$PLIST"

# Adopt builds launched before the registry existed, before the first tick classifies anything.
WALKAWAY_HOME="$WALKAWAY_HOME" bash "${SCRIPT_DIR}/lib/adopt.sh" "${WALKAWAY_LAUNCH_LOG_GLOB:-/tmp/walkaway-*.log}"

touch "${WALKAWAY_HOME}/supervisor.enabled"
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$PLIST"
launchctl enable "$DOMAIN/$LABEL"
echo "Supervisor loaded: $LABEL (every 120s) → ${WALKAWAY_HOME}/logs/supervisor.log"
launchctl print "$DOMAIN/$LABEL" | grep -E '^\s*(state|run interval|last exit code)' || true
