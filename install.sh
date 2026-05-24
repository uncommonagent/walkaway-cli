#!/usr/bin/env bash
# Installs the walkaway CLI by symlinking walkaway.sh into your PATH.
# Re-running is safe (idempotent).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALKAWAY_SH="${SCRIPT_DIR}/walkaway.sh"

if [[ ! -f "$WALKAWAY_SH" ]]; then
  echo "ERROR: walkaway.sh not found at $WALKAWAY_SH" >&2
  exit 1
fi

chmod +x "$WALKAWAY_SH"
chmod +x "${SCRIPT_DIR}/lib/"*.sh

# Pick install dir: prefer /usr/local/bin if writable, else ~/.local/bin
if [[ -w "/usr/local/bin" ]]; then
  INSTALL_DIR="/usr/local/bin"
else
  INSTALL_DIR="${HOME}/.local/bin"
  mkdir -p "$INSTALL_DIR"
fi

LINK_PATH="${INSTALL_DIR}/walkaway"

if [[ -L "$LINK_PATH" ]]; then
  echo "Updating symlink: $LINK_PATH → $WALKAWAY_SH"
  ln -sf "$WALKAWAY_SH" "$LINK_PATH"
elif [[ -e "$LINK_PATH" ]]; then
  echo "ERROR: $LINK_PATH exists and is not a symlink. Remove it manually." >&2
  exit 1
else
  echo "Installing: $LINK_PATH → $WALKAWAY_SH"
  ln -s "$WALKAWAY_SH" "$LINK_PATH"
fi

# Ensure INSTALL_DIR is in PATH
if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
  echo ""
  echo "NOTE: $INSTALL_DIR is not in your PATH."
  echo "Add this to your ~/.zshrc or ~/.bashrc:"
  echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
fi

echo ""
echo "Done. Run: walkaway --help"
