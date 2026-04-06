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
   git branch -M main
   git remote add origin <REPO_URL>
   git fetch origin
   ```
2. If the remote has commits: `git reset origin/main` to bring in repo files without overwriting existing local files. Then check out files that exist in the remote but not locally (new files from other machines), and always force-checkout the scripts:
   ```bash
   git diff --name-only --diff-filter=D | xargs -I{} git checkout -- {}
   git checkout -- sync-hook.sh .gitignore
   ```
   **Important**: do NOT read `settings.json` after this step — step 5 handles it. After `git reset`, the git index may differ from the working tree for files that existed locally; ignore the index and proceed directly to step 4.
3. If the remote is empty: create the scaffolding files (`sync-hook.sh`, `.gitignore`) in `~/.claude/` — see "Scaffolding Files" section below.
4. Run `chmod +x ~/.claude/sync-hook.sh`
5. **ALWAYS run this command** — even if you think the hook might already be present. It merges remote and local settings.json, reports conflicts, and adds the sync hook:
   ```bash
   python3 -c "
   import json, os, subprocess
   path = os.path.expanduser('~/.claude/settings.json')
   local = json.load(open(path)) if os.path.exists(path) else {}
   try:
       remote_str = subprocess.check_output(['git', 'show', 'HEAD:settings.json'], cwd=os.path.expanduser('~/.claude'), stderr=subprocess.DEVNULL).decode()
       remote = json.loads(remote_str)
   except Exception:
       remote = {}
   # Detect conflicts and merge non-conflicting keys
   conflicts = []
   def merge(base, override, path_prefix=''):
       result = dict(base)
       for k, v in override.items():
           key_path = f'{path_prefix}.{k}' if path_prefix else k
           if k in result and isinstance(result[k], dict) and isinstance(v, dict):
               result[k] = merge(result[k], v, key_path)
           elif k in result and result[k] != v:
               conflicts.append((key_path, result[k], v))
               result[k] = v  # local wins by default, user can override
           else:
               result[k] = v
       return result
   settings = merge(remote, local)
   if conflicts:
       print('CONFLICTS DETECTED:')
       for key, remote_val, local_val in conflicts:
           print(f'  {key}: remote={json.dumps(remote_val)} vs local={json.dumps(local_val)}')
   # Add sync hook
   hook_cmd = 'bash ~/.claude/sync-hook.sh'
   hooks = settings.setdefault('hooks', {})
   session_hooks = hooks.setdefault('SessionStart', [])
   if not any(h.get('command') == hook_cmd for e in session_hooks for h in e.get('hooks', [])):
       session_hooks.insert(0, {'hooks': [{'type': 'command', 'command': hook_cmd, 'timeout': 30, 'statusMessage': 'Syncing claude config...'}]})
   with open(path, 'w') as f: json.dump(settings, f, indent=2); f.write('\n')
   print('SessionStart hook configured in', path)
   "
   ```
   If the output shows `CONFLICTS DETECTED`, present each conflict to the user (showing the remote value vs local value) and ask which to keep. Then update `~/.claude/settings.json` accordingly.
   After running, verify by reading `~/.claude/settings.json` and confirming `"bash ~/.claude/sync-hook.sh"` appears in it.
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
