#!/usr/bin/env bash
# Watcher for walkaway build handoff directories.
#
# When run directly (as the background process):
#   bash lib/watcher.sh <handoff-dir> <feature-name>
#
# When sourced by walkaway.sh:
#   source lib/watcher.sh
#   watcher_start <handoff-dir> <feature-name>   # start in background
#   watcher_stop  <feature-name>                 # kill background process
#   watcher_running <feature-name>               # returns 0 if running

WALKAWAY_STATE_DIR="${WALKAWAY_STATE_DIR:-$HOME/.walkaway-cli/state}"
WALKAWAY_LOG_DIR="${WALKAWAY_LOG_DIR:-$HOME/.walkaway-cli/logs}"
NTFY_TOPIC="${NTFY_TOPIC:-jim-throughline-9k2x7q-builds}"

# ── internal: notification helper ─────────────────────────────────────────────
_watcher_notify() {
  local title="$1" body="$2" priority="${3:-default}"
  curl -s \
    -H "Title: $title" \
    -H "Priority: $priority" \
    -H "Tags: hammer,wrench" \
    -d "$body" \
    "https://ntfy.sh/$NTFY_TOPIC" > /dev/null 2>&1 || true
  echo "[$(date +%H:%M:%S)] notified: $title"
}

# ── internal: the actual watch loop (runs as background process) ──────────────
_watcher_loop() {
  local handoff_dir="$1"
  local feature="$2"
  local state_file="${WALKAWAY_STATE_DIR}/.watcher-state-${feature}"

  mkdir -p "$(dirname "$state_file")"

  # Initialize state with current files so we don't fire on startup
  if [[ ! -f "$state_file" ]]; then
    touch "$state_file"
    for f in "$handoff_dir"/*.md; do
      [[ -f "$f" ]] || continue
      local mtime fname
      mtime=$(stat -f %m "$f")
      fname=$(basename "$f")
      printf '%s\t%s\n' "$fname" "$mtime" >> "$state_file"
    done
  fi

  echo "[$(date +%H:%M:%S)] watching $handoff_dir (feature: $feature)"

  while true; do
    for f in "$handoff_dir"/*.md; do
      [[ -f "$f" ]] || continue
      local filename mtime
      filename=$(basename "$f")
      mtime=$(stat -f %m "$f")

      if grep -qF "${filename}	${mtime}" "$state_file" 2>/dev/null; then
        continue
      fi

      local fired=0
      case "$filename" in
        "build-report-${feature}.md")
          _watcher_notify "Build complete: $feature" "Build report ready. Say 'status $feature'." "high"
          fired=1
          ;;
        failure-report-*"${feature}"*)
          _watcher_notify "Build STOPPED: $feature" "$filename — check the failure report." "urgent"
          fired=1
          ;;
        # Everything else (build-report-CURRENT.md, other features' reports,
        # phase/codex/smoke files) is marked seen silently. Each watcher fires
        # exactly ONCE for its own feature, then exits — so watchers never
        # accumulate and never cross-fire on another build's shared files.
      esac

      # Update state
      grep -v "^${filename}	" "$state_file" > "${state_file}.tmp" 2>/dev/null || true
      printf '%s\t%s\n' "$filename" "$mtime" >> "${state_file}.tmp"
      mv "${state_file}.tmp" "$state_file"

      # Self-terminate after firing for this feature: one build, one ping, done.
      if [[ "$fired" -eq 1 ]]; then
        rm -f "${WALKAWAY_STATE_DIR}/watcher-${feature}.json" "$state_file" 2>/dev/null || true
        exit 0
      fi
    done
    sleep 15
  done
}

# ── public: check if watcher is running for a feature ─────────────────────────
watcher_running() {
  local feature="$1"
  local pid_file="${WALKAWAY_STATE_DIR}/watcher-${feature}.json"
  [[ ! -f "$pid_file" ]] && return 1
  local pid
  pid=$(grep '"pid"' "$pid_file" | grep -o '[0-9]*' | head -1)
  [[ -z "$pid" ]] && return 1
  kill -0 "$pid" 2>/dev/null
}

# ── public: start watcher in background ───────────────────────────────────────
watcher_start() {
  local handoff_dir="$1"
  local feature="$2"
  local dry_run="${3:-false}"
  local pid_file="${WALKAWAY_STATE_DIR}/watcher-${feature}.json"
  local log_file="${WALKAWAY_LOG_DIR}/watcher-${feature}.log"

  if watcher_running "$feature"; then
    local pid
    pid=$(grep '"pid"' "$pid_file" | grep -o '[0-9]*' | head -1)
    echo "Watcher already running for '$feature' (PID $pid). Use --force to restart."
    return 1
  fi

  if [[ "$dry_run" == "true" ]]; then
    echo "  [dry-run] would start watcher → $log_file"
    return 0
  fi

  mkdir -p "$WALKAWAY_STATE_DIR" "$WALKAWAY_LOG_DIR"

  # The watcher loop script path (this file, run directly)
  local this_script
  this_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/watcher.sh"

  nohup bash "$this_script" --loop "$handoff_dir" "$feature" \
    >> "$log_file" 2>&1 &
  local watcher_pid=$!
  disown "$watcher_pid"

  # Write state JSON
  cat > "$pid_file" <<JSONEOF
{
  "pid": ${watcher_pid},
  "log": "${log_file}",
  "feature": "${feature}",
  "handoff_dir": "${handoff_dir}",
  "started": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSONEOF

  echo "Watcher started (PID $watcher_pid) → $log_file"
}

# ── public: stop watcher ──────────────────────────────────────────────────────
watcher_stop() {
  local feature="$1"
  local pid_file="${WALKAWAY_STATE_DIR}/watcher-${feature}.json"

  if ! watcher_running "$feature"; then
    echo "No running watcher for '$feature'."
    return 0
  fi

  local pid
  pid=$(grep '"pid"' "$pid_file" | grep -o '[0-9]*' | head -1)
  kill "$pid" 2>/dev/null && echo "Watcher stopped (PID $pid)." || true
  rm -f "$pid_file"
}

# ── entry point when run directly ─────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ "${1:-}" == "--loop" ]]; then
    shift
    _watcher_loop "$@"
  else
    echo "Usage: watcher.sh --loop <handoff-dir> <feature-name>" >&2
    echo "  (Normally started via watcher_start from walkaway.sh)" >&2
    exit 1
  fi
fi
