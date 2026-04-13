---
name: claude-everywhere
description: Set up and manage cross-machine syncing of Claude Code configuration (~/.claude/ directory) using git. Use when the user asks about syncing Claude Code settings across machines, sharing CLAUDE.md between computers, keeping slash commands and skills in sync, or setting up Claude Code on a new machine.
license: MIT
metadata:
  author: jokerwyt
  version: "2.1"
compatibility: Requires git. Works on macOS and Linux.
---

# claude-everywhere: Cross-Machine Claude Code Config Sync

Sync your `~/.claude/` directory (CLAUDE.md, settings.json, skills, commands) across all machines using git + a SessionStart hook.

## How It Works

The `~/.claude/` directory is a git repo. A SessionStart hook runs on every Claude Code launch:

1. `git add -A && git commit` — commits any local changes
2. `git pull --rebase --autostash` — pulls remote changes
3. `git push` — pushes merged state

A `.gitignore` whitelist controls what gets synced (only explicitly listed patterns are tracked).

## Setup Instructions

The user will provide a git repo URL (from the README). The repo can be empty or contain existing claude-everywhere files. Since setup is always done from within Claude Code, `~/.claude/` already exists.

> **⚠️ CRITICAL: Do NOT use the skill repo as the sync repo!**
>
> The sync repo must be the user's **own private repo** for storing their config — NOT this skill/template repo.
> If the user provides a URL that points to the `claude-everywhere` skill repo itself, **STOP immediately** and ask them for their correct sync repo URL.

0. **Validate the repo URL** — before doing anything else, check that the user's URL is NOT the skill repo. **STOP and alert the user** if the URL matches any of these patterns (case-insensitive, with or without `.git` suffix, with or without trailing slash):
   - `github.com/jokerwyt/claude-everywhere`
   - `github.com/*/claude-everywhere` (any fork of the skill repo)
   - Any URL where the repo name is exactly `claude-everywhere` (not `claude-everywhere-syncing`, `claude-everywhere-myconfig`, etc.)

   The sync repo should be a **separate, private repo** (e.g. `claude-everywhere-syncing`, `my-claude-config`, etc.) that the user created to store their own config. If validation fails, tell the user:
   *"You provided the URL of the claude-everywhere skill repo, not your sync repo. The skill repo contains the setup template — your sync repo should be a separate private repo you created to store your config. Please provide the correct URL."*

1. **Backup** — before any changes, back up the user's current config:
   ```bash
   cp -a ~/.claude ~/.claude.bak.$(date +%Y%m%d%H%M%S)
   ```
   Tell the user the backup path.

2. Initialize git and connect to remote:
   ```bash
   cd ~/.claude
   git init
   git branch -M main
   git remote add origin <REPO_URL>
   git fetch origin
   ```
3. **If the remote has commits** (i.e., another machine already set up):
   a. Checkout `.gitignore` and `sync-hook.sh` from remote so `.gitignore` takes effect:
      ```bash
      git checkout origin/main -- .gitignore sync-hook.sh
      ```
   b. Commit all local tracked files (`.gitignore` filters out conversations/caches):
      ```bash
      git add -A && git commit -m "local state before merge"
      ```
   c. Merge remote into local — git handles conflicts natively:
      ```bash
      git merge origin/main --allow-unrelated-histories -m "merge remote config"
      ```
      If there are merge conflicts (e.g., in `settings.json` or `CLAUDE.md`), show the conflicts to the user and ask how to resolve. After resolving, run `git add -A && git commit`.
4. **If the remote is empty**: create the scaffolding files (`sync-hook.sh`, `.gitignore`) in `~/.claude/` — see "Scaffolding Files" section below.
5. Run `chmod +x ~/.claude/sync-hook.sh`
6. **ALWAYS run this command** — it is idempotent. Adds the sync hook to `settings.json` (creates it if missing, preserves all existing keys):
   ```bash
   python3 -c "
   import json, os
   path = os.path.expanduser('~/.claude/settings.json')
   settings = json.load(open(path)) if os.path.exists(path) else {}
   hook_cmd = 'bash ~/.claude/sync-hook.sh'
   hooks = settings.setdefault('hooks', {})
   session_hooks = hooks.setdefault('SessionStart', [])
   if not any(h.get('command') == hook_cmd for e in session_hooks for h in e.get('hooks', [])):
       session_hooks.insert(0, {'hooks': [{'type': 'command', 'command': hook_cmd, 'timeout': 30, 'statusMessage': 'Syncing claude config...'}]})
   with open(path, 'w') as f: json.dump(settings, f, indent=2); f.write('\n')
   print('SessionStart hook configured in', path)
   "
   ```
   After running, verify by reading `~/.claude/settings.json` and confirming `"bash ~/.claude/sync-hook.sh"` appears in it.
7. Commit and push: `git add -A && git commit -m "initial sync" && git push -u origin main`

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
