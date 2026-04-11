#!/bin/bash
# Claude Code Shared Memory Setup — WSL side
# Usage: bash setup.sh <wsl-user> <windows-user> <project-name> [distro-name]
# Example: bash setup.sh wsluser winuser MyProject
# Example: bash setup.sh wsluser winuser MyProject Ubuntu-22.04

set -eo pipefail

WSL_USER="${1}"
WIN_USER="${2}"
PROJECT="${3}"
DISTRO="${4:-Ubuntu-24.04}"

if [[ -z "$WSL_USER" || -z "$WIN_USER" || -z "$PROJECT" ]]; then
  echo "Usage: bash setup.sh <wsl-user> <windows-user> <project-name> [distro-name]"
  echo "Example: bash setup.sh wsluser winuser MyProject"
  echo "Example: bash setup.sh wsluser winuser MyProject Ubuntu-22.04"
  exit 1
fi

# Validate project name — spaces and slashes break the hash
if [[ "$PROJECT" =~ [[:space:]/] ]]; then
  echo "Error: project name must not contain spaces or slashes: '$PROJECT'"
  echo "Use the folder name as it appears under ~/.claude/projects/ (e.g. Claude-home-ai-infra)"
  exit 1
fi

# Sanitize distro name for use in hash (replace spaces and dots with hyphens)
# Claude Code replaces both when deriving the project hash from the WSL path.
# e.g. "Ubuntu-24.04" → "Ubuntu-24-04"
DISTRO_SLUG=$(echo "$DISTRO" | tr ' .' '-')

WSL_HASH="-home-${WSL_USER}-${PROJECT}"
WIN_HASH="--wsl-localhost-${DISTRO_SLUG}-home-${WSL_USER}-${PROJECT}"

WSL_MEMORY="/home/${WSL_USER}/.claude/projects/${WSL_HASH}/memory"
WIN_MEMORY="/home/${WSL_USER}/.claude/projects/${WIN_HASH}/memory"

echo "WSL project hash : ${WSL_HASH}"
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

# Bind mount (skip if already mounted — idempotent)
if findmnt -n "${WIN_MEMORY}" > /dev/null 2>&1; then
  echo "Already mounted — skipping bind mount."
else
  echo "Bind mounting memory directory..."
  sudo mount --bind "${WSL_MEMORY}" "${WIN_MEMORY}"
fi

# Persist via fstab
FSTAB_ENTRY="${WSL_MEMORY} ${WIN_MEMORY} none bind 0 0"

if grep -qF "${FSTAB_ENTRY}" /etc/fstab; then
  echo "fstab entry already exists, skipping."
else
  echo "Adding fstab entry for persistence..."
  echo "${FSTAB_ENTRY}" | sudo tee -a /etc/fstab > /dev/null
fi

echo ""
echo "Done. Now run the PowerShell step (see README) to symlink C:\Users\\${WIN_USER}\\.claude to WSL."
echo ""
echo "To verify the mount:"
echo "  findmnt ${WIN_MEMORY}"
