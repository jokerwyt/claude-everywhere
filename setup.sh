#!/bin/bash
# Bootstrap script for ClaudeEverywhere config sync system.
# Usage: git clone git@github.com:YOUR_USERNAME/ClaudeEverywhere.git ~/.claude && bash ~/.claude/setup.sh
set -euo pipefail
cd ~/.claude

echo "=== ClaudeEverywhere Setup ==="

# 1. Switch to main branch
CURRENT=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
if [ "$CURRENT" != "main" ]; then
  echo "Switching from '$CURRENT' to 'main'..."
  git checkout main 2>/dev/null || git checkout -b main origin/main
fi

# 2. Make sync-hook.sh executable
chmod +x sync-hook.sh
echo "✓ sync-hook.sh is executable"

# 3. Merge SessionStart hook into settings.json
SETTINGS="$HOME/.claude/settings.json"
python3 -c "
import json, os, sys

path = sys.argv[1]
# Read existing settings
if os.path.exists(path):
    with open(path) as f:
        settings = json.load(f)
else:
    settings = {}

# Add SessionStart hook (if not already present)
hook_cmd = 'bash ~/.claude/sync-hook.sh'
hooks = settings.setdefault('hooks', {})
session_hooks = hooks.setdefault('SessionStart', [])

# Check if sync hook already exists
already = any(
    h.get('command') == hook_cmd
    for entry in session_hooks
    for h in entry.get('hooks', [])
)

if not already:
    session_hooks.append({
        'hooks': [{
            'type': 'command',
            'command': hook_cmd,
            'timeout': 30,
            'statusMessage': 'Syncing claude config...'
        }]
    })
    print('✓ SessionStart hook added')
else:
    print('✓ SessionStart hook already configured')

with open(path, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
print('✓ settings.json updated')
" "$SETTINGS"

echo ""
echo "=== Setup complete ==="
echo "Every time Claude Code starts, it will auto-sync config via git."
echo "To add files to sync, edit ~/.claude/.gitignore (whitelist pattern)."
