---
name: claude-everywhere
description: Set up and manage cross-machine syncing of Claude Code configuration (~/.claude/ directory) using git. Use when the user asks about syncing Claude Code settings across machines, sharing CLAUDE.md between computers, keeping slash commands and skills in sync, or setting up Claude Code on a new machine.
license: MIT
metadata:
  author: jokerwyt
  version: "2.1"
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

The user will provide a git repo URL (from the README). The repo can be empty or contain existing ClaudeEverywhere files. Since setup is always done from within Claude Code, `~/.claude/` already exists.

1. Initialize git and connect to remote:
   ```bash
   cd ~/.claude
   git init
   git remote add origin <REPO_URL>
   git fetch origin
   ```
2. If the remote has commits: `git reset origin/main` to bring in repo files without overwriting existing local files. Then `git checkout -- sync-hook.sh .gitignore` to ensure scripts are present. **Note**: after `git reset`, the git index may differ from the working tree — always read files from disk (not via `git show`) in subsequent steps.
3. If the remote is empty: create the scaffolding files (`sync-hook.sh`, `.gitignore`) in `~/.claude/` — see "Scaffolding Files" section below.
4. Run `chmod +x ~/.claude/sync-hook.sh`
5. Read the **current** `~/.claude/settings.json` from disk (NOT from git index). Merge the SessionStart hook into it. The user's existing keys (permissions, model, etc.) MUST be preserved — only add the `hooks.SessionStart` entry if the `"bash ~/.claude/sync-hook.sh"` command is not already present. If there are already other SessionStart hooks, insert the sync hook as the **first** entry in the array (it must run before other hooks so config is up-to-date). **Warn the user** that existing SessionStart hooks were found and that the sync hook was inserted before them. The hook entry to merge:
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
6. Commit and push: `git add -A && git commit -m "initial sync" && git push -u origin main`

## Scaffolding Files

When setting up with an empty repo, create these files in `~/.claude/`:

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
