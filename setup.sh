#!/bin/bash
# Claude Code Shared Memory Setup — WSL side
#
# Usage:
#   bash setup.sh <wsl-user> <windows-user> <project-name> [distro-name]
#   bash setup.sh verify <wsl-user> <project-name> [distro-name]
#
# Examples:
#   bash setup.sh alice bob my-project
#   bash setup.sh alice bob my-project Ubuntu-22.04
#   bash setup.sh verify alice my-project
#   bash setup.sh verify alice my-project Ubuntu-22.04

set -eo pipefail

# ── colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; RESET='\033[0m'
pass() { echo -e "  ${GREEN}✓${RESET} $*"; }
fail() { echo -e "  ${RED}✗${RESET} $*"; }
warn() { echo -e "  ${YELLOW}!${RESET} $*"; }

# ── shared hash computation ───────────────────────────────────────────────────

_compute_hashes() {
  local wsl_user="$1" project="$2" distro="$3"

  # Sanitize distro name — Claude Code replaces spaces and dots with hyphens
  # e.g. "Ubuntu-24.04" → "Ubuntu-24-04"
  local distro_slug
  distro_slug=$(echo "$distro" | tr ' .' '-')

  WSL_HASH="-home-${wsl_user}-${project}"
  WIN_HASH="--wsl-localhost-${distro_slug}-home-${wsl_user}-${project}"
  WSL_MEMORY="/home/${wsl_user}/.claude/projects/${WSL_HASH}/memory"
  WIN_MEMORY="/home/${wsl_user}/.claude/projects/${WIN_HASH}/memory"
}

# ── verify ────────────────────────────────────────────────────────────────────

cmd_verify() {
  local wsl_user="${1:-}"
  local project="${2:-}"
  local distro="${3:-Ubuntu-24.04}"

  if [[ -z "$wsl_user" || -z "$project" ]]; then
    echo "Usage: bash setup.sh verify <wsl-user> <project-name> [distro-name]"
    exit 1
  fi

  _compute_hashes "$wsl_user" "$project" "$distro"

  echo ""
  echo "Computed hashes:"
  echo "  WSL  : ${WSL_HASH}"
  echo "  Win  : ${WIN_HASH}"
  echo ""

  local issues=0

  # WSL memory directory exists
  if [[ -d "$WSL_MEMORY" ]]; then
    pass "WSL memory directory exists: ${WSL_MEMORY}"
  else
    fail "WSL memory directory NOT found: ${WSL_MEMORY}"
    echo "     → Open the project in WSL Claude CLI at least once to create it."
    ((issues++))
  fi

  # Windows hash directory exists
  if [[ -d "$WIN_MEMORY" ]]; then
    pass "Windows hash directory exists: ${WIN_MEMORY}"
  else
    fail "Windows hash directory NOT found: ${WIN_MEMORY}"
    echo "     → Run: bash setup.sh ${wsl_user} <win-user> ${project} ${distro}"
    ((issues++))
  fi

  # Bind mount is active
  if findmnt -n "${WIN_MEMORY}" > /dev/null 2>&1; then
    pass "Bind mount is active"
  else
    fail "Bind mount is NOT active"
    echo "     → Run: sudo mount -a"
    ((issues++))
  fi

  # fstab entry exists
  if grep -qF "${WSL_MEMORY}" /etc/fstab 2>/dev/null; then
    pass "fstab entry present (mount will persist across restarts)"
  else
    warn "No fstab entry — mount will not survive WSL restart"
    echo "     → Re-run setup to add it."
  fi

  echo ""
  if [[ "$issues" -eq 0 ]]; then
    echo -e "${GREEN}All checks passed — memory sharing is active.${RESET}"
  else
    echo -e "${RED}${issues} issue(s) found — memory sharing is broken.${RESET}"
    exit 1
  fi
}

# ── install ───────────────────────────────────────────────────────────────────

cmd_install() {
  local wsl_user="${1:-}"
  local win_user="${2:-}"
  local project="${3:-}"
  local distro="${4:-Ubuntu-24.04}"

  if [[ -z "$wsl_user" || -z "$win_user" || -z "$project" ]]; then
    echo "Usage: bash setup.sh <wsl-user> <windows-user> <project-name> [distro-name]"
    echo "Example: bash setup.sh alice bob my-project"
    echo "Example: bash setup.sh alice bob my-project Ubuntu-22.04"
    echo ""
    echo "To verify an existing setup:"
    echo "  bash setup.sh verify <wsl-user> <project-name> [distro-name]"
    exit 1
  fi

  # Validate project name — spaces and slashes break the hash
  if [[ "$project" =~ [[:space:]/] ]]; then
    echo "Error: project name must not contain spaces or slashes: '$project'"
    echo "Use the folder name as it appears under ~/.claude/projects/ (e.g. Claude-home-ai-infra)"
    exit 1
  fi

  _compute_hashes "$wsl_user" "$project" "$distro"

  echo ""
  echo "WSL project hash  : ${WSL_HASH}"
  echo "Windows project hash : ${WIN_HASH}"
  echo ""

  # Verify WSL memory directory exists
  if [[ ! -d "$WSL_MEMORY" ]]; then
    echo "Error: WSL memory directory not found at ${WSL_MEMORY}"
    echo "Make sure Claude Code has been opened from WSL at least once."
    exit 1
  fi

  # Create Windows hash directory
  echo "Creating Windows project directory..."
  mkdir -p "${WIN_MEMORY}"

  # Bind mount (idempotent)
  if findmnt -n "${WIN_MEMORY}" > /dev/null 2>&1; then
    echo "Already mounted — skipping bind mount."
  else
    echo "Bind mounting memory directory..."
    sudo mount --bind "${WSL_MEMORY}" "${WIN_MEMORY}"
  fi

  # Persist via fstab
  local fstab_entry="${WSL_MEMORY} ${WIN_MEMORY} none bind 0 0"
  if grep -qF "${fstab_entry}" /etc/fstab; then
    echo "fstab entry already exists, skipping."
  else
    echo "Adding fstab entry for persistence..."
    echo "${fstab_entry}" | sudo tee -a /etc/fstab > /dev/null
  fi

  echo ""
  echo "Done. Now run the PowerShell step (see README) to symlink C:\Users\\${win_user}\\.claude to WSL."
  echo ""
  echo "Verify the setup at any time:"
  echo "  bash setup.sh verify ${wsl_user} ${project} ${distro}"
}

# ── dispatch ──────────────────────────────────────────────────────────────────

CMD="${1:-}"

case "$CMD" in
  verify) shift; cmd_verify "$@" ;;
  *)      cmd_install "$@" ;;
esac
