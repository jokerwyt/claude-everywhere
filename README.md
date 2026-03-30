# ClaudeEverywhere

Sync your Claude Code configuration (`~/.claude/`) across all your machines using git.

Every time Claude Code starts, a SessionStart hook automatically commits local changes, pulls remote updates, and pushes — so your `CLAUDE.md`, `settings.json`, custom skills, and slash commands stay in sync. A `.gitignore` whitelist ensures only config files are tracked; conversation logs, caches, and other runtime data stay local.

## Setup — Join Sync

1. Create a **private** GitHub repo to store your config (can be empty).
2. Fill in your repo URL at the bottom of this file.
3. Copy the prompt below and paste it into Claude Code. It will handle the rest.

```
Read the SKILL.md at this repo and follow its instructions to set up config sync
for this machine. If ~/.claude already exists, use the "Existing ~/.claude Directory"
flow to preserve my existing files. If not, use the "New Setup" flow.
```

Repeat step 3 on every machine you want to sync.

## Uninstall — Leave Sync

Copy the prompt below and paste it into Claude Code. Your config files (CLAUDE.md, settings.json, skills, commands) will NOT be deleted — only the sync mechanism is removed.

```
Remove ClaudeEverywhere from this machine:
1. Remove the SessionStart hook entry containing "sync-hook.sh" from ~/.claude/settings.json
2. Delete these files: ~/.claude/.git, ~/.claude/sync-hook.sh, ~/.claude/.gitignore
3. Keep everything else (CLAUDE.md, settings.json, skills, commands) intact
```

## License

MIT

---

Private repo: `git@github.com:YOUR_USERNAME/YOUR_REPO.git`
