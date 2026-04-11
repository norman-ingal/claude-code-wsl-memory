# Claude Code Shared Memory — Windows + WSL

> **Who this is for:** Developers using Claude Code on **Windows** who also run Claude Code inside **WSL** (Ubuntu or any distro) — and want both instances to share the same memory and context.
>
> **macOS / Linux users:** You don't have this problem. Claude Code runs natively and memory is stored in one place.

---

## The Problem

Claude Code builds up memory about your projects — your preferences, decisions, architecture, things you've told it to remember. This memory makes every session smarter than the last.

But on Windows + WSL, you effectively have **two isolated Claude instances** that never talk to each other:

| Instance | Memory location |
|---|---|
| Windows app (opening `\\wsl.localhost\Ubuntu-24.04\...`) | `C:\Users\<winuser>\.claude\projects\--wsl-localhost-Ubuntu-24-04-home-<user>-<project>\` |
| WSL CLI (`claude` in terminal) | `~/.claude/projects/-home-<user>-<project>\` |

Different hashes, different directories, different memory. Whatever the Windows app learns, the WSL CLI doesn't know — and vice versa.

**After this fix:** both instances read and write the same memory files. Context built in one is immediately available in the other.

---

## How It Works

```
Windows Claude Code
  └── C:\Users\winuser\.claude          ← symlink
        └── \\wsl.localhost\...\home\wsluser\.claude   (WSL filesystem)
              └── projects/
                    ├── -home-wsluser-MyProject/     ← WSL hash (canonical)
                    │     └── memory/  ← one source of truth
                    └── --wsl-localhost-...-MyProject/  ← Windows hash
                          └── memory/  ← bind mounted from above
```

Two steps:
1. **Symlink** `C:\Users\<winuser>\.claude` → WSL's `~/.claude` — same config directory
2. **Bind mount** the WSL memory folder onto the Windows hash folder — same memory files

---

## Prerequisites

- Windows 11 with WSL2
- Claude Code installed on both Windows (desktop app) and WSL (CLI)
- Admin PowerShell access (for the symlink)
- Your WSL username and Windows username — run `whoami` in each to confirm (they may differ)

---

## Setup

### Step 1 — Find your project name

The `<project-name>` is derived from the WSL path of your project. Run this in WSL to find it:

```bash
ls ~/.claude/projects/
```

Look for a folder starting with `-home-<wsluser>-`. Everything after `-home-<wsluser>-` is your project name. For example:

```
-home-alice-my-project   →  project name is  my-project
-home-alice-myapp        →  project name is  myapp
```

> **Tip:** If you haven't opened the project in WSL CLI yet, do that first — it creates the memory directory.

### Step 2 — Run the WSL setup script

Clone this repo and run the script from your WSL terminal:

```bash
git clone https://github.com/norman-ingal/claude-code-wsl-memory.git
cd claude-code-wsl-memory
bash setup.sh <wsl-user> <windows-user> <project-name> [distro-name]
```

Examples:

```bash
# Ubuntu 24.04 (default)
bash setup.sh alice alice my-project

# Different distro — must exactly match output of `wsl --list`
bash setup.sh alice alice my-project Ubuntu-22.04
```

This will:
- Create the Windows project hash directory in WSL
- Bind mount the WSL memory folder onto it
- Add the mount to `/etc/fstab` so it persists across WSL restarts

**Repeat for each project you want to share.**

### Step 3 — Symlink Windows `.claude` to WSL (Admin PowerShell)

Open PowerShell as Administrator and run:

```powershell
# Back up existing Windows Claude config
Rename-Item "C:\Users\<winuser>\.claude" "C:\Users\<winuser>\.claude.bak"

# Symlink it to WSL
New-Item -ItemType SymbolicLink `
  -Path "C:\Users\<winuser>\.claude" `
  -Target "\\wsl.localhost\Ubuntu-24.04\home\<wsluser>\.claude"
```

Replace `Ubuntu-24.04` with your actual distro name if different.

### Step 4 — Verify it works

1. Restart the Windows Claude Code app
2. Open your project in the **Windows app** and tell Claude something to remember:
   ```
   Please remember that I prefer TypeScript over JavaScript for this project.
   ```
3. Open the same project in **WSL CLI** and ask:
   ```
   What do you remember about this project?
   ```

If it recalls what you told the Windows app, memory sharing is working.

---

## If Memory Stops Working After WSL Restart

The bind mount may not have reapplied. Run in WSL:

```bash
sudo mount -a
```

To check if the mount is active:

```bash
findmnt ~/.claude/projects/--wsl-localhost-Ubuntu-24-04-home-<wsluser>-<project>
```

---

## Tips for a Seamless Experience

### Add a `CLAUDE.md` to each project

Claude Code reads `CLAUDE.md` at the start of every session. Use it to encode project-specific instructions that apply to both instances — including the git workarounds below. This means you never have to re-explain context, and both Windows and WSL sessions behave consistently.

Example `CLAUDE.md` additions:

```markdown
## Git operations

# Push must run inside WSL (SSH agent lives there):
wsl -d Ubuntu-24.04 -- bash -c "cd /home/<wsluser>/<repo> && git push"

# Pull at session start:
wsl -d Ubuntu-24.04 -- bash -c "cd /home/<wsluser>/<repo> && git pull"
```

### Use `CURRENT_WORK.md` as a session handoff

Create a `CURRENT_WORK.md` in your repo and instruct Claude to update it at the end of every session. It becomes a machine-readable handoff note — any session, on any machine, starts with full context.

---

## Known Issues

### Git push hangs when Claude runs commands from Windows

When the Windows Claude Code app runs shell commands against a repo at a `//wsl.localhost/` path, it uses a Windows-side bash environment that **cannot reach WSL's SSH agent**. Any git operation requiring SSH auth (`git push`, `git fetch`, `git pull` over SSH) hangs indefinitely.

**Fix — run git push inside WSL:**

```bash
wsl -d Ubuntu-24.04 -- bash -c "cd /home/<wsluser>/<repo> && git push"
```

Add this pattern to your `CLAUDE.md` so Claude handles it automatically every session.

### Git "dubious ownership" error

Git may refuse to run in repos accessed via `//wsl.localhost/` paths due to a filesystem ownership mismatch between Windows and WSL.

**Fix:**

```bash
git config --global --add safe.directory '%(prefix)///wsl.localhost/Ubuntu-24.04/home/<wsluser>/<repo>'
```

Or route all git commands through WSL (recommended — avoids the issue entirely).

### Git identity not set on Windows sessions

Git commits from Windows-side bash may fail with "Author identity unknown" if `user.name` and `user.email` aren't set in the repo's local config.

**Fix — set per repo:**

```bash
wsl -d Ubuntu-24.04 -- bash -c "
  cd /home/<wsluser>/<repo>
  git config user.name 'Your Name'
  git config user.email 'your@email.com'
"
```

Or add it to your bootstrap/setup script so it's set automatically on every new clone.

---

## Security

See [SECURITY.md](SECURITY.md) for the dependency update policy and secrets rules.
