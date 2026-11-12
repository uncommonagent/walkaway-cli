#!/usr/bin/env bash
# One-line ntfy notifications for the supervisor and operator. Every send is also appended to
# $WALKAWAY_HOME/logs/ntfy.log so "exactly one ntfy per transition" is auditable locally.

WALKAWAY_HOME="${WALKAWAY_HOME:-$HOME/.walkaway-cli}"
NTFY_TOPIC="${NTFY_TOPIC:-jim-throughline-9k2x7q-builds}"
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"

# notify_line <message> [priority]   priority: default | high | urgent
notify_line() {
  local msg="$1" priority="${2:-default}"
  mkdir -p "${WALKAWAY_HOME}/logs"
  printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$NTFY_TOPIC" "$priority" "$msg" >> "${WALKAWAY_HOME}/logs/ntfy.log"
  [[ "${WALKAWAY_NTFY_DISABLED:-}" == "1" ]] && return 0
  curl -s -m 15 \
    -H "Priority: $priority" \
    -H "Tags: robot" \
    -d "$msg" \
    "${NTFY_SERVER}/${NTFY_TOPIC}" > /dev/null 2>&1 || true
}
