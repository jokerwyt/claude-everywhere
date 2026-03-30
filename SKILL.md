---
name: claude-everywhere
description: Set up and manage cross-machine syncing of Claude Code configuration (~/.claude/ directory) using git. Use when the user asks about syncing Claude Code settings across machines, sharing CLAUDE.md between computers, keeping slash commands and skills in sync, or setting up Claude Code on a new machine.
license: MIT
metadata:
  author: jokerwyt
  version: "2.0"
compatibility: Requires git. Works on macOS and Linux.
---

# ClaudeEverywhere: Cross-Machine Claude Code Config Sync

Sync your `~/.claude/` directory (CLAUDE.md, settings.json, skills, commands) across all machines using git + a SessionStart hook.

## How It Works

The `~/.claude/` directory is a git repo. A SessionStart hook runs on every Claude Code launch:

1. `git add -A && git commit` — commits any local changes
2. `git pull --rebase --autostash` — pulls remote changes
3. `git push` — pushes merged state

A `.gitignore` whitelist controls what gets synced (only explicitly listed patterns are tracked).

## Setup Instructions

The user will provide a git repo URL. The repo can be empty or contain existing ClaudeEverywhere files.

### New Setup (no existing ~/.claude)

1. Clone the repo:
   ```bash
   git clone <REPO_URL> ~/.claude
   ```
2. If the repo is empty, copy the scaffolding files (`sync-hook.sh`, `.gitignore`) into `~/.claude/` and create an initial commit.
3. Run `chmod +x ~/.claude/sync-hook.sh`
4. Merge the SessionStart hook into `~/.claude/settings.json` (create if missing). The hook entry must be:
   ```json
   {
     "hooks": {
       "SessionStart": [
         {
           "hooks": [
             {
               "type": "command",
               "command": "bash ~/.claude/sync-hook.sh",
               "timeout": 30,
               "statusMessage": "Syncing claude config..."
             }
           ]
         }
       ]
     }
   }
   ```
   **Important**: merge this into existing settings.json — do NOT overwrite existing keys (permissions, model, etc.). Only add the SessionStart hook if not already present.
5. Commit and push: `git add -A && git commit -m "initial sync" && git push -u origin main`

### Existing ~/.claude Directory

1. Initialize git and connect to remote:
   ```bash
   cd ~/.claude
   git init
   git remote add origin <REPO_URL>
   git fetch origin
   ```
2. If the remote has commits: `git reset origin/main` to bring in repo files without overwriting existing local files. Then `git checkout -- sync-hook.sh .gitignore` to ensure scripts are present.
3. If the remote is empty: copy the scaffolding files (`sync-hook.sh`, `.gitignore`) into `~/.claude/`.
4. Run `chmod +x ~/.claude/sync-hook.sh`
5. Merge the SessionStart hook into `~/.claude/settings.json` (same JSON structure as above). Preserve all existing settings.
6. Commit and push: `git add -A && git commit -m "initial sync" && git push -u origin main`

### Additional Machines

Same as "New Setup" — clone, set up hook, sync.

## Scaffolding Files

When setting up an empty repo, you need to create these files in `~/.claude/`:

### .gitignore
```gitignore
# Only track config files that should sync across machines
*
!.gitignore
!settings.json
!CLAUDE.md
!commands/
!commands/**
!skills/
!skills/**
!sync-hook.sh
```

### sync-hook.sh
The sync-hook.sh file is in this same repo. Read it and copy it to `~/.claude/sync-hook.sh`.

## What Gets Synced

Default whitelist (edit `.gitignore` to add more):
- `CLAUDE.md` — global instructions
- `settings.json` — Claude Code settings
- `commands/` — custom slash commands (recursive)
- `skills/` — custom skills (recursive)
- `sync-hook.sh` — the sync system itself

## Adding Files to Sync

Edit `.gitignore` and add `!pattern`:

```gitignore
!memory/
!memory/*.md
```

## Troubleshooting

### Rebase Conflict
If you see "Rebase conflict!", run:
```bash
cd ~/.claude && git pull --rebase
```
Resolve conflicts, then `git rebase --continue`.

### Timeout
Git operations have a 15s internal timeout (30s hook timeout). If network is slow, the hook skips gracefully. Next launch will retry.

## Documenting the Sync in CLAUDE.md

Add a section to your `CLAUDE.md` so Claude understands the sync system. See `CLAUDE.md.example` for a template.
