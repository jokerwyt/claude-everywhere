# ClaudeEverywhere

Sync your Claude Code configuration (`~/.claude/`) across all your machines using git.

Your `CLAUDE.md`, `settings.json`, custom skills, and slash commands stay in sync automatically — every time Claude Code starts, a SessionStart hook commits local changes, pulls remote updates, and pushes.

## How It Works

```
Machine A starts Claude Code
  → SessionStart hook fires
  → git add -A && git commit (local changes)
  → git pull --rebase --autostash (remote changes)
  → git push (share back)

Machine B starts Claude Code
  → Same cycle — picks up Machine A's changes
```

The sync is controlled by a `.gitignore` whitelist — only explicitly listed file patterns are tracked. Everything else (conversation logs, caches, etc.) stays local.

## Quick Start

Prerequisites: Fork this repo on GitHub first (e.g., `your-username/ClaudeEverywhere`).

The easiest way to set up is to give this repo's URL to Claude Code and ask it to help you install:

```
Give Claude: https://github.com/YOUR_USERNAME/ClaudeEverywhere
Ask: "Help me set up ClaudeEverywhere for syncing my ~/.claude config"
```

Or set up manually:

### Fresh machine (no existing `~/.claude`)

```bash
git clone git@github.com:YOUR_USERNAME/ClaudeEverywhere.git ~/.claude
bash ~/.claude/setup.sh
```

### Existing `~/.claude` directory

```bash
cd ~/.claude
git init
git remote add origin git@github.com:YOUR_USERNAME/ClaudeEverywhere.git
git fetch origin
git reset origin/main          # bring in repo files without overwriting existing
git checkout -- sync-hook.sh setup.sh .gitignore  # ensure scripts are present

# Run setup (merges SessionStart hook into existing settings.json)
bash setup.sh

# Commit & push your existing config
git add -A && git commit -m "initial sync" && git push -u origin main
```

### Additional machines

```bash
git clone git@github.com:YOUR_USERNAME/ClaudeEverywhere.git ~/.claude
bash ~/.claude/setup.sh
```

## What Gets Synced

Controlled by `.gitignore` (whitelist pattern — everything is ignored except explicitly listed files):

| Pattern | What it includes |
|---------|-----------------|
| `CLAUDE.md` | Your global instructions |
| `settings.json` | Claude Code settings (hooks, permissions, etc.) |
| `commands/` | Custom slash commands (recursive) |
| `skills/` | Custom skills (recursive) |
| `sync-hook.sh` | The sync script itself |
| `setup.sh` | The bootstrap script |

### Adding More Files to Sync

Edit `.gitignore` and add a `!filename` or `!pattern` entry:

```gitignore
# Example: also sync your memory files
!memory/
!memory/*.md
```

Since `sync-hook.sh` uses `git add -A`, any un-ignored file will be automatically committed and synced.

## Conflict Handling

If `git pull --rebase` encounters a conflict:

1. The hook aborts the rebase safely
2. You'll see a warning: `Rebase conflict! Run: cd ~/.claude && git pull --rebase to resolve.`
3. Resolve manually or ask Claude: `cd ~/.claude && git pull --rebase`

## Settings.json Merge

`setup.sh` **merges** the SessionStart hook into your existing `settings.json` — it does not overwrite. Your existing permissions, model preferences, and other settings are preserved.

If you sync `settings.json` across machines, be aware that machine-specific settings (like file paths) will be shared. You can choose not to sync it by removing `!settings.json` from `.gitignore`.

## Timeout & Error Handling

There are two timeout layers:

- **Hook timeout (30s)**: Set in `settings.json` — Claude Code kills the entire hook if it exceeds this limit.
- **Internal timeout (15s)**: Set in `sync-hook.sh` — each individual git operation (`pull`, `push`) is capped at 15s so a slow network doesn't consume the full hook budget.

If a git operation times out (e.g., no network), the hook skips gracefully and the next launch will retry. The hook outputs a JSON status message that Claude Code displays.

## FAQ

**Q: What if I edit CLAUDE.md on two machines at the same time?**
A: The next sync will attempt a rebase. If the edits don't conflict, it merges automatically. If they do, you'll get a conflict warning and can resolve it.

**Q: Can I use HTTPS instead of SSH?**
A: Yes. Clone with `https://github.com/...` instead. You may need to configure a credential helper for push.

**Q: Will this sync my conversation history?**
A: No. The `.gitignore` whitelist only tracks the files you explicitly allow. Conversation logs, caches, and other runtime files stay local.

**Q: What if `setup.sh` fails?**
A: It requires Python 3 (for JSON merging). Most systems have this. If not, you can manually add the hook to `settings.json` — see `settings.json.example`.

## Uninstall

To stop syncing and remove ClaudeEverywhere:

```bash
# 1. Remove the SessionStart hook from settings.json
python3 -c "
import json
path = '$HOME/.claude/settings.json'
with open(path) as f:
    s = json.load(f)
hooks = s.get('hooks', {}).get('SessionStart', [])
s['hooks']['SessionStart'] = [
    e for e in hooks
    if not any(h.get('command') == 'bash ~/.claude/sync-hook.sh' for h in e.get('hooks', []))
]
if not s['hooks']['SessionStart']:
    del s['hooks']['SessionStart']
if not s['hooks']:
    del s['hooks']
with open(path, 'w') as f:
    json.dump(s, f, indent=2)
    f.write('\n')
print('Hook removed from settings.json')
"

# 2. Remove git tracking (keeps your files intact)
rm -rf ~/.claude/.git ~/.claude/sync-hook.sh ~/.claude/setup.sh
```

Your `CLAUDE.md`, `settings.json`, skills, and commands remain untouched — only the git sync is removed.

## License

MIT
