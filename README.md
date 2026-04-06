# claude-everywhere

Sync your Claude Code configuration (`~/.claude/`) across all your machines using git.

Every time Claude Code starts, a SessionStart hook automatically commits local changes, pulls remote updates, and pushes — so your `CLAUDE.md`, `settings.json`, custom skills, and slash commands stay in sync. A `.gitignore` whitelist ensures only config files are tracked; conversation logs, caches, and other runtime data stay local.

## What Gets Synced

The default `.gitignore` whitelist syncs these files:

- `CLAUDE.md` — global instructions for Claude
- `settings.json` — Claude Code settings (hooks, permissions, model, etc.)
- `commands/` — custom slash commands (recursive)
- `skills/` — custom skills (recursive)
- `sync-hook.sh` — the sync script itself

Everything else in `~/.claude/` (conversations, caches, sessions) stays local. To add more files, edit `.gitignore` and add `!pattern`.

## Setup — Join Sync

**Prerequisites**: Git and SSH key (or HTTPS token) configured for GitHub on this machine.

1. Create a **private** empty GitHub repo to store your config.
2. Copy the prompt below, replace `<YOUR REPO ADDRESS>` with your private repo URL, and paste it into Claude Code.

```
Run: git clone https://github.com/jokerwyt/claude-everywhere.git /tmp/claude-everywhere
Then read /tmp/claude-everywhere/SKILL.md and follow its instructions to set up config sync for this machine.
My private github repo for synchronizing: <YOUR REPO ADDRESS>
```

Repeat on every machine you want to sync.

## Uninstall — Leave Sync

Copy the prompt below and paste it into Claude Code. Your config files (CLAUDE.md, settings.json, skills, commands) will NOT be deleted — only the sync mechanism is removed.

```
Remove claude-everywhere from this machine. Run these two commands:
1. python3 -c "
   import json, os, shutil
   path = os.path.expanduser('~/.claude/settings.json')
   s = json.load(open(path)) if os.path.exists(path) else {}
   s.get('hooks', {})['SessionStart'] = [e for e in s.get('hooks', {}).get('SessionStart', []) if not any(h.get('command', '') == 'bash ~/.claude/sync-hook.sh' for h in e.get('hooks', []))]
   if not s['hooks']['SessionStart']: del s['hooks']['SessionStart']
   if not s['hooks']: del s['hooks']
   with open(path, 'w') as f: json.dump(s, f, indent=2); f.write('\n')
   print('Hook removed from', path)
   "
2. python3 -c "
   import os, shutil
   base = os.path.expanduser('~/.claude')
   for f in ['.git', 'sync-hook.sh', '.gitignore']:
       p = os.path.join(base, f)
       if os.path.isdir(p): shutil.rmtree(p)
       elif os.path.exists(p): os.remove(p)
       print('Removed', p)
   "
3. Read ~/.claude/CLAUDE.md and remove the "Config Sync System" section (and any other claude-everywhere related content). Keep everything else unchanged.
```

## License

MIT