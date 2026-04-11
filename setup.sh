#!/bin/bash
# Claude Code Shared Memory Setup — WSL side
#
# Usage:
#   bash setup.sh install <wsl-user> <project-name> [distro-name]
#   bash setup.sh verify  <wsl-user> <project-name> [distro-name]
#   bash setup.sh uninstall <wsl-user> <project-name> [distro-name]
#
# Examples:
#   bash setup.sh install alice my-project
#   bash setup.sh install alice my-project Ubuntu-22.04
#   bash setup.sh verify  alice my-project
#   bash setup.sh uninstall alice my-project

set -eo pipefail

# ── colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'
pass() { echo -e "  ${GREEN}✓${RESET} $*"; }
fail() { echo -e "  ${RED}✗${RESET} $*"; }
warn() { echo -e "  ${YELLOW}!${RESET} $*"; }
info() { echo -e "  ${BOLD}→${RESET} $*"; }

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

_require_args() {
  local cmd="$1" wsl_user="$2" project="$3"
  if [[ -z "$wsl_user" || -z "$project" ]]; then
    echo "Usage: bash setup.sh ${cmd} <wsl-user> <project-name> [distro-name]"
    exit 1
  fi
  if [[ "$project" =~ [[:space:]/] ]]; then
    echo "Error: project name must not contain spaces or slashes: '$project'"
    echo "Use the folder name as it appears under ~/.claude/projects/ (e.g. Claude-home-ai-infra)"
    exit 1
  fi
}

# ── install ───────────────────────────────────────────────────────────────────

cmd_install() {
  local wsl_user="${1:-}"
  local project="${2:-}"
  local distro="${3:-Ubuntu-24.04}"

  _require_args install "$wsl_user" "$project"
  _compute_hashes "$wsl_user" "$project" "$distro"

  echo ""
  echo "WSL project hash     : ${WSL_HASH}"
  echo "Windows project hash : ${WIN_HASH}"
  echo ""

  # Verify WSL memory directory exists
  if [[ ! -d "$WSL_MEMORY" ]]; then
    echo "Error: WSL memory directory not found at ${WSL_MEMORY}"
    echo "Open the project in WSL Claude CLI at least once to create it, then re-run."
    exit 1
  fi

  # Create Windows hash directory
  info "Creating Windows project directory..."
  mkdir -p "${WIN_MEMORY}"

  # Bind mount (idempotent)
  if findmnt -n "${WIN_MEMORY}" > /dev/null 2>&1; then
    pass "Already mounted — skipping bind mount."
  else
    info "Bind mounting memory directory..."
    sudo mount --bind "${WSL_MEMORY}" "${WIN_MEMORY}"
    pass "Bind mount active."
  fi

  # Persist via fstab
  local fstab_entry="${WSL_MEMORY} ${WIN_MEMORY} none bind 0 0"
  if grep -qF "${fstab_entry}" /etc/fstab; then
    pass "fstab entry already present."
  else
    info "Adding fstab entry for persistence..."
    echo "${fstab_entry}" | sudo tee -a /etc/fstab > /dev/null
    pass "fstab entry added."
  fi

  echo ""
  echo "WSL side done. Now symlink the Windows .claude directory (Admin PowerShell):"
  echo ""
  echo "  Rename-Item \"C:\Users\<your-windows-username>\.claude\" \"C:\Users\<your-windows-username>\.claude.bak\""
  echo "  New-Item -ItemType SymbolicLink \\"
  echo "    -Path \"C:\Users\<your-windows-username>\.claude\" \\"
  echo "    -Target \"\\\\wsl.localhost\\${distro}\home\\${wsl_user}\.claude\""
  echo ""
  echo "Verify at any time:"
  echo "  bash setup.sh verify ${wsl_user} ${project} ${distro}"
}

# ── verify ────────────────────────────────────────────────────────────────────

cmd_verify() {
  local wsl_user="${1:-}"
  local project="${2:-}"
  local distro="${3:-Ubuntu-24.04}"

  _require_args verify "$wsl_user" "$project"
  _compute_hashes "$wsl_user" "$project" "$distro"

  echo ""
  echo "Computed hashes:"
  echo "  WSL  : ${WSL_HASH}"
  echo "  Win  : ${WIN_HASH}"
  echo ""

  local issues=0

  # WSL memory directory exists
  if [[ -d "$WSL_MEMORY" ]]; then
    pass "WSL memory directory exists"
  else
    fail "WSL memory directory NOT found: ${WSL_MEMORY}"
    echo "     → Open the project in WSL Claude CLI at least once to create it."
    ((issues++))
  fi

  # Windows hash directory exists
  if [[ -d "$WIN_MEMORY" ]]; then
    pass "Windows hash directory exists"
  else
    fail "Windows hash directory NOT found: ${WIN_MEMORY}"
    echo "     → Run: bash setup.sh install ${wsl_user} ${project} ${distro}"
    echo "     → If the directory name looks wrong, check: ls ~/.claude/projects/"
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
    pass "fstab entry present (survives WSL restart)"
  else
    warn "No fstab entry — mount will not survive WSL restart"
    echo "     → Re-run: bash setup.sh install ${wsl_user} ${project} ${distro}"
  fi

  echo ""
  if [[ "$issues" -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}All checks passed — memory sharing is active.${RESET}"
  else
    echo -e "${RED}${BOLD}${issues} issue(s) found — memory sharing is broken.${RESET}"
    exit 1
  fi
}

# ── uninstall ─────────────────────────────────────────────────────────────────

cmd_uninstall() {
  local wsl_user="${1:-}"
  local project="${2:-}"
  local distro="${3:-Ubuntu-24.04}"

  _require_args uninstall "$wsl_user" "$project"
  _compute_hashes "$wsl_user" "$project" "$distro"

  echo ""
  echo "Uninstalling memory share for: ${project}"
  echo ""

  # Unmount
  if findmnt -n "${WIN_MEMORY}" > /dev/null 2>&1; then
    info "Unmounting bind mount..."
    sudo umount "${WIN_MEMORY}"
    pass "Unmounted."
  else
    pass "No active mount — skipping umount."
  fi

  # Remove fstab entry
  local fstab_entry="${WSL_MEMORY} ${WIN_MEMORY} none bind 0 0"
  if grep -qF "${fstab_entry}" /etc/fstab 2>/dev/null; then
    info "Removing fstab entry..."
    sudo sed -i "\|${fstab_entry}|d" /etc/fstab
    pass "fstab entry removed."
  else
    pass "No fstab entry — skipping."
  fi

  # Remove Windows hash directory (now empty)
  if [[ -d "$WIN_MEMORY" ]]; then
    info "Removing Windows hash directory..."
    rmdir "${WIN_MEMORY}" 2>/dev/null || warn "Directory not empty — leaving in place: ${WIN_MEMORY}"
    [[ ! -d "$WIN_MEMORY" ]] && pass "Directory removed."
  fi

  echo ""
  echo "WSL side done. To fully revert, also remove the Windows symlink (Admin PowerShell):"
  echo ""
  echo "  Remove-Item \"C:\Users\<your-windows-username>\.claude\""
  echo "  Rename-Item \"C:\Users\<your-windows-username>\.claude.bak\" \"C:\Users\<your-windows-username>\.claude\""
  echo ""
  pass "Uninstall complete."
}

# ── dispatch ──────────────────────────────────────────────────────────────────

CMD="${1:-help}"
shift || true

case "$CMD" in
  install)   cmd_install "$@" ;;
  verify)    cmd_verify "$@" ;;
  uninstall) cmd_uninstall "$@" ;;
  help|--help|-h|"")
    echo ""
    echo "Usage: bash setup.sh <command> <wsl-user> <project-name> [distro-name]"
    echo ""
    echo "  install    Set up memory sharing for a project"
    echo "  verify     Check that memory sharing is active and healthy"
    echo "  uninstall  Remove the bind mount and fstab entry for a project"
    echo ""
    echo "Examples:"
    echo "  bash setup.sh install   alice my-project"
    echo "  bash setup.sh install   alice my-project Ubuntu-22.04"
    echo "  bash setup.sh verify    alice my-project"
    echo "  bash setup.sh uninstall alice my-project"
    echo ""
    ;;
  *)
    echo "Unknown command: $CMD — run 'bash setup.sh help'"
    exit 1
    ;;
esac
