# ClaudeEverywhere

Sync your Claude Code configuration (`~/.claude/`) across all your machines using git.

Every time Claude Code starts, a SessionStart hook automatically commits local changes, pulls remote updates, and pushes — so your `CLAUDE.md`, `settings.json`, custom skills, and slash commands stay in sync. A `.gitignore` whitelist ensures only config files are tracked; conversation logs, caches, and other runtime data stay local.

## Setup — Join Sync

Prerequisites: create a private GitHub repo to store your config (can be empty).

Paste the following into Claude Code, replacing the repo URL with yours:

```
Read the SKILL.md at git@github.com:YOUR_USERNAME/YOUR_REPO.git and follow its
instructions to set up config sync for this machine. The repo URL is the one above.
If ~/.claude already exists, use the "Existing ~/.claude Directory" flow to preserve
my existing files. If not, use the "New Setup" flow.
```

## Uninstall — Leave Sync

Paste the following into Claude Code:

```
Remove ClaudeEverywhere from this machine:
1. Remove the SessionStart hook entry containing "sync-hook.sh" from ~/.claude/settings.json
2. Delete these files: ~/.claude/.git, ~/.claude/sync-hook.sh, ~/.claude/.gitignore
3. Keep everything else (CLAUDE.md, settings.json, skills, commands) intact
```

## License

MIT
