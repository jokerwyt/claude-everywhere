---
name: claude-everywhere
description: Set up and manage cross-machine syncing of Claude Code configuration (~/.claude/ directory) using git. Use when the user asks about syncing Claude Code settings across machines, sharing CLAUDE.md between computers, keeping slash commands and skills in sync, or setting up Claude Code on a new machine.
license: MIT
metadata:
  author: jokerwyt
  version: "1.0"
compatibility: Requires git and Python 3. Works on macOS and Linux.
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

### New Setup (no existing ~/.claude)

```bash
# 1. Fork the repo on GitHub, then:
git clone git@github.com:YOUR_USERNAME/ClaudeEverywhere.git ~/.claude
bash ~/.claude/setup.sh
```

### Existing ~/.claude Directory

```bash
# 1. Back up
cp -r ~/.claude ~/.claude.bak

# 2. Clone (remove existing dir first)
rm -rf ~/.claude
git clone git@github.com:YOUR_USERNAME/ClaudeEverywhere.git ~/.claude

# 3. Restore your files
cp ~/.claude.bak/CLAUDE.md ~/.claude/CLAUDE.md
cp -r ~/.claude.bak/skills ~/.claude/skills
cp -r ~/.claude.bak/commands ~/.claude/commands

# 4. Run setup
bash ~/.claude/setup.sh
```

### Additional Machines

```bash
git clone git@github.com:YOUR_USERNAME/ClaudeEverywhere.git ~/.claude
bash ~/.claude/setup.sh
```

## What Gets Synced

Default whitelist (edit `.gitignore` to add more):
- `CLAUDE.md` — global instructions
- `settings.json` — Claude Code settings
- `commands/*.md` — custom slash commands
- `skills/*/*.md` — custom skills
- `sync-hook.sh`, `setup.sh` — the sync system itself

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
Git operations have a 15s timeout. If network is slow, the hook skips gracefully. Next launch will retry.

### setup.sh Fails
Requires Python 3 for JSON merging. Alternatively, manually add the hook — see `settings.json.example`.

## Documenting the Sync in CLAUDE.md

Add a section to your `CLAUDE.md` so Claude understands the sync system. See `CLAUDE.md.example` for a template.
