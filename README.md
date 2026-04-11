# Claude Code Shared Memory — Windows + WSL

Fix for Claude Code on Windows not sharing memory with Claude Code running in WSL (Ubuntu).

## The Problem

When you open a project via `//wsl.localhost/Ubuntu-24.04/...` in the Windows Claude Code app, it generates a different project hash than when you open the same project from inside WSL. This means:

- **WSL Claude Code** stores memory under `~/.claude/projects/-home-<user>-<project>/`
- **Windows Claude Code** stores memory under `~/.claude/projects/--wsl-localhost-Ubuntu-24-04-home-<user>-<project>/`

On top of that, the Windows app stores its `.claude` directory under `C:\Users\<winuser>\.claude`, completely separate from WSL's `~/.claude`.

Result: two isolated Claude instances that never share context or memory.

## The Fix

Two steps:

1. **Symlink** `C:\Users\<winuser>\.claude` → WSL's `~/.claude` so both apps use the same config directory
2. **Bind mount** the WSL project's memory folder onto the Windows project hash folder so both hashes read the same memory files

## Prerequisites

- Windows 11 with WSL2 (Ubuntu 24.04 or any distro)
- Claude Code installed on both Windows and WSL
- Admin PowerShell access
- Your WSL username and Windows username (may differ)

## Setup

### Step 1 — Run the WSL setup script

In your WSL terminal:

```bash
bash setup.sh <wsl-user> <windows-user> <project-name> [distro-name]
```

Example (Ubuntu 24.04, the default):

```bash
bash setup.sh wsluser winuser MyProject
```

Example (different distro):

```bash
bash setup.sh wsluser winuser MyProject Ubuntu-22.04
```

The distro name must exactly match what appears in `wsl --list` — it determines the Windows project hash. Defaults to `Ubuntu-24.04` if omitted.

This will:
- Create the Windows project hash directory in WSL
- Bind mount the memory folder
- Add the bind mount to `/etc/fstab` for persistence

### Step 2 — Symlink Windows `.claude` to WSL (Admin PowerShell)

```powershell
Rename-Item "C:\Users\<winuser>\.claude" "C:\Users\<winuser>\.claude.bak"
New-Item -ItemType SymbolicLink -Path "C:\Users\<winuser>\.claude" -Target "\\wsl.localhost\Ubuntu-24.04\home\<wsluser>\.claude"
```

Example:

```powershell
Rename-Item "C:\Users\winuser\.claude" "C:\Users\winuser\.claude.bak"
New-Item -ItemType SymbolicLink -Path "C:\Users\winuser\.claude" -Target "\\wsl.localhost\Ubuntu-24.04\home\wsluser\.claude"
```

### Step 3 — Restart Windows Claude Code

Reopen the Windows Claude Code app. Both instances now share the same memory.

## If Memory Stops Working After WSL Restart

The bind mount may not have reapplied. Run:

```bash
sudo mount -a
```

## How It Works

```
Windows Claude Code
  └── C:\Users\winuser\.claude          (symlink)
        └── \\wsl.localhost\...\home\wsluser\.claude   (WSL filesystem)
              └── projects/
                    ├── -home-wsluser-MyProject/          (WSL hash)
                    │     └── memory/  ← canonical
                    └── --wsl-localhost-...-MyProject/    (Windows hash)
                          └── memory/  ← bind mounted from above
```

Both project hashes point to the same memory files. Writes from either app are immediately visible to the other.

## Known Issues

### Git push hangs when Claude runs commands from Windows

When the Windows Claude Code app runs shell commands against a repo at a `//wsl.localhost/` path, it uses a Windows-side bash environment that cannot reach WSL's SSH agent. Any git operation that requires SSH auth (`git push`, `git fetch`, `git pull` with an SSH remote) will hang indefinitely.

**Fix:** Tell Claude to run git push via WSL explicitly:

```bash
wsl -d Ubuntu-24.04 -- bash -c "cd /home/<wsluser>/<repo> && git push"
```

Or add this to your project's `CLAUDE.md` so Claude knows to do it automatically:

```markdown
For git push, always use:
wsl -d Ubuntu-24.04 -- bash -c "cd /home/<wsluser>/<repo> && git push"
```

### Git "dubious ownership" error

Git may refuse to run in repos accessed via `//wsl.localhost/` paths due to a filesystem ownership mismatch. Fix with:

```bash
git config --global --add safe.directory '%(prefix)///wsl.localhost/Ubuntu-24.04/home/<wsluser>/<repo>'
```

Or run all git commands inside WSL to avoid the issue entirely.
