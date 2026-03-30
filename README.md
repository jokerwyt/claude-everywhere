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

### 1. Fork this repo

Click **Fork** on GitHub to create your own copy (e.g., `your-username/ClaudeEverywhere`).

### 2. Back up existing config (if any)

```bash
# If you already have ~/.claude with content you want to keep:
cp -r ~/.claude ~/.claude.bak
```

### 3. Clone to `~/.claude`

```bash
# Remove or move existing ~/.claude directory first
mv ~/.claude ~/.claude.bak  # or: rm -rf ~/.claude

git clone git@github.com:YOUR_USERNAME/ClaudeEverywhere.git ~/.claude
```

### 4. Restore your existing files

```bash
# Copy back your CLAUDE.md, skills, commands, etc.
cp ~/.claude.bak/CLAUDE.md ~/.claude/CLAUDE.md
cp -r ~/.claude.bak/skills ~/.claude/skills
cp -r ~/.claude.bak/commands ~/.claude/commands
# ... any other files you want to sync
```

### 5. Run setup

```bash
bash ~/.claude/setup.sh
```

This will:
- Switch to the `main` branch
- Make `sync-hook.sh` executable
- Add the SessionStart hook to your `settings.json` (merge, not overwrite — existing settings are preserved)

### 6. Start Claude Code

The next time Claude Code starts, it will automatically sync your config.

## What Gets Synced

Controlled by `.gitignore` (whitelist pattern — everything is ignored except explicitly listed files):

| Pattern | What it includes |
|---------|-----------------|
| `CLAUDE.md` | Your global instructions |
| `settings.json` | Claude Code settings (hooks, permissions, etc.) |
| `commands/*.md` | Custom slash commands |
| `skills/` + `skills/*/*.md` | Custom skills |
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

- Git operations have a 15-second internal timeout
- If a pull/push times out (e.g., no network), the hook skips gracefully
- The hook outputs a JSON status message that Claude Code displays

## Setting Up Additional Machines

On each new machine:

```bash
git clone git@github.com:YOUR_USERNAME/ClaudeEverywhere.git ~/.claude
bash ~/.claude/setup.sh
```

That's it. Every machine shares the same `main` branch.

## FAQ

**Q: What if I edit CLAUDE.md on two machines at the same time?**
A: The next sync will attempt a rebase. If the edits don't conflict, it merges automatically. If they do, you'll get a conflict warning and can resolve it.

**Q: Can I use HTTPS instead of SSH?**
A: Yes. Clone with `https://github.com/...` instead. You may need to configure a credential helper for push.

**Q: Will this sync my conversation history?**
A: No. The `.gitignore` whitelist only tracks the files you explicitly allow. Conversation logs, caches, and other runtime files stay local.

**Q: What if `setup.sh` fails?**
A: It requires Python 3 (for JSON merging). Most systems have this. If not, you can manually add the hook to `settings.json` — see `settings.json.example`.

## Agent Skill

This repo includes a `SKILL.md` file following the [Agent Skills](https://agentskills.io) specification. You can install it as a skill:

```bash
npx skills add YOUR_USERNAME/ClaudeEverywhere
```

## License

MIT
