#!/bin/bash
# Comprehensive E2E test using real Claude Code sessions (via -p mode).
# Tests setup, cross-machine sync, hook auto-fire, conflict resolution, and uninstall.
# Uses stream-json for live feedback during Claude calls.
#
# Usage: bash test-claude.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_ROOT=$(mktemp -d)
REMOTE="$TEST_ROOT/remote.git"
HOME_A="$TEST_ROOT/home_a"
HOME_B="$TEST_ROOT/home_b"
PASS=0; FAIL=0

cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT

green() { printf "\033[32m✓ %s\033[0m\n" "$1"; }
red()   { printf "\033[31m✗ %s\033[0m\n" "$1"; }
dim()   { printf "\033[90m  %s\033[0m\n" "$1"; }
assert() {
  local result
  result=$(set +eo pipefail; eval "$2" 2>/dev/null && echo 1 || echo 0)
  if [ "$result" = "1" ]; then green "$1"; PASS=$((PASS+1)); else red "$1"; FAIL=$((FAIL+1)); fi
}

# Run claude -p with stream-json, show live progress
# Usage: run_claude HOME_DIR EXTRA_FLAGS... -- "prompt"
run_claude() {
  local home="$1"; shift
  local flags=()
  while [ $# -gt 1 ]; do flags+=("$1"); shift; done
  local prompt="$1"

  HOME="$home" claude \
    -p --output-format stream-json --verbose \
    --dangerously-skip-permissions \
    "${flags[@]}" \
    "$prompt" < /dev/null 2>/dev/null | while IFS= read -r line; do

    local type subtype
    type=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('type',''))" 2>/dev/null) || continue
    subtype=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('subtype',''))" 2>/dev/null) || true

    case "$type" in
      system)
        case "$subtype" in
          hook_started)
            local hname
            hname=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('hook_name',''))" 2>/dev/null) || true
            dim "[hook] $hname started"
            ;;
          hook_response)
            local outcome
            outcome=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('outcome',''))" 2>/dev/null) || true
            dim "[hook] $outcome"
            ;;
        esac
        ;;
      assistant)
        local content_json
        content_json=$(echo "$line" | python3 -c "
import sys, json
msg = json.load(sys.stdin).get('message', {})
for block in msg.get('content', []):
    t = block.get('type', '')
    if t == 'tool_use':
        print(f\"[tool] {block.get('name', '?')}\")
    elif t == 'text':
        text = block.get('text', '')
        if text.strip():
            print(text.strip()[:80])
" 2>/dev/null) || true
        if [ -n "$content_json" ]; then
          while IFS= read -r cline; do
            dim "$cline"
          done <<< "$content_json"
        fi
        ;;
      result)
        local dur cost
        dur=$(echo "$line" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"{d.get('duration_ms',0)//1000}s\")" 2>/dev/null) || true
        cost=$(echo "$line" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"\${d.get('total_cost_usd',0):.4f}\")" 2>/dev/null) || true
        dim "[done] ${dur} ${cost}"
        ;;
    esac
  done
}

# Simulate Claude Code session start (triggers sync hook)
restart_claude() {
  local home="$1"
  HOME="$home" bash "$home/.claude/sync-hook.sh" 2>/dev/null || true
}

# Exact prompts from README — no extra hints
SETUP_PROMPT_TEMPLATE='Read the SKILL.md at this repo and follow its instructions to set up config sync
for this machine.
My private github repo for synchronizing: %s'

UNINSTALL_PROMPT=$(cat <<'EOFPROMPT'
Remove ClaudeEverywhere from this machine. Run these two commands:
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
EOFPROMPT
)

echo "=== ClaudeEverywhere Comprehensive E2E Test ==="
echo "Test root: $TEST_ROOT"
echo ""

# --- Prep: bare remote + fake HOMEs ---
echo "--- Prep ---"
git init --bare "$REMOTE" >/dev/null 2>&1
seed=$(mktemp -d)
git clone "$REMOTE" "$seed/repo" >/dev/null 2>&1
cp "$REPO_DIR"/{sync-hook.sh,.gitignore,SKILL.md} "$seed/repo/"
(cd "$seed/repo" && git add -A && git commit -m "init" >/dev/null 2>&1 && git push >/dev/null 2>&1)
rm -rf "$seed"

for h in "$HOME_A" "$HOME_B"; do
  n=$(basename "$h"); mkdir -p "$h/.claude"
  git config --file "$h/.gitconfig" user.name "Test $n"
  git config --file "$h/.gitconfig" user.email "$n@test.com"
done
green "Remote repo + test homes ready"

# Format setup prompt with actual repo URL
SETUP_PROMPT=$(printf "$SETUP_PROMPT_TEMPLATE" "$REMOTE")

# ==========================================================
# Step 1: Machine A — setup via exact README prompt
# ==========================================================
echo ""
echo "--- Step 1: Machine A setup (claude -p --bare) ---"

run_claude "$HOME_A" \
  --bare --system-prompt-file "$REPO_DIR/SKILL.md" \
  -- "$SETUP_PROMPT"

echo ""
assert "A: settings.json exists" "[ -f '$HOME_A/.claude/settings.json' ]"
assert "A: hook configured" "grep -q 'sync-hook.sh' '$HOME_A/.claude/settings.json' 2>/dev/null"
assert "A: sync-hook.sh executable" "[ -x '$HOME_A/.claude/sync-hook.sh' ]"
assert "A: is git repo" "[ -d '$HOME_A/.claude/.git' ]"

# ==========================================================
# Step 2: Machine A — add CLAUDE.md + sync via hook
# ==========================================================
echo ""
echo "--- Step 2: Machine A adds CLAUDE.md + syncs ---"

cat > "$HOME_A/.claude/CLAUDE.md" << 'EOF'
# Shared Config
- MARKER_FROM_A
- Use TypeScript everywhere
EOF

restart_claude "$HOME_A"
assert "A: CLAUDE.md committed+pushed" "git -C '$REMOTE' log --oneline main 2>/dev/null | grep -q 'auto-sync'"

# ==========================================================
# Step 3: Machine B (dirty) — setup via exact README prompt
# ==========================================================
echo ""
echo "--- Step 3: Machine B (dirty state) setup ---"

# Create dirty state: CLAUDE.md, commands, skills, custom settings
echo "# MARKER_FROM_B" > "$HOME_B/.claude/CLAUDE.md"
echo "Personal notes from B" >> "$HOME_B/.claude/CLAUDE.md"
mkdir -p "$HOME_B/.claude/commands"
echo "deploy command content" > "$HOME_B/.claude/commands/deploy.md"
mkdir -p "$HOME_B/.claude/skills/my-skill"
cat > "$HOME_B/.claude/skills/my-skill/SKILL.md" << 'SKILLEOF'
---
name: my-skill
description: A custom skill from Machine B
---
# My Skill
Do something cool.
SKILLEOF
cat > "$HOME_B/.claude/settings.json" << 'EOF'
{
  "permissions": {"allow": ["bash"]},
  "model": "opus"
}
EOF

run_claude "$HOME_B" \
  --bare --system-prompt-file "$REPO_DIR/SKILL.md" \
  -- "$SETUP_PROMPT"

echo ""
assert "B: hook configured" "grep -q 'sync-hook.sh' '$HOME_B/.claude/settings.json' 2>/dev/null"
assert "B: CLAUDE.md preserved" "grep -q 'MARKER_FROM_B' '$HOME_B/.claude/CLAUDE.md' 2>/dev/null"
assert "B: deploy.md preserved" "[ -f '$HOME_B/.claude/commands/deploy.md' ]"
assert "B: skill preserved" "[ -f '$HOME_B/.claude/skills/my-skill/SKILL.md' ]"
assert "B: permissions preserved" "grep -q 'opus' '$HOME_B/.claude/settings.json' 2>/dev/null"
# Note: B's existing CLAUDE.md is preserved — A's content is NOT merged into it.
# B's version will be pushed on first sync; A will get B's version on next pull.

# ==========================================================
# Step 4: Machine B — modify + sync via hook
# ==========================================================
echo ""
echo "--- Step 4: Machine B modifies CLAUDE.md + syncs ---"

echo "- MARKER_B_EDIT" >> "$HOME_B/.claude/CLAUDE.md"
restart_claude "$HOME_B"
assert "B: changes pushed" "git -C '$HOME_B/.claude' diff --quiet origin/main 2>/dev/null"

# ==========================================================
# Step 5: Machine A — sync, verify B's changes
# ==========================================================
echo ""
echo "--- Step 5: Machine A syncs — gets B's changes ---"

restart_claude "$HOME_A"
assert "A: got B's marker" "grep -q 'MARKER_FROM_B' '$HOME_A/.claude/CLAUDE.md' 2>/dev/null"
assert "A: got B's edit" "grep -q 'MARKER_B_EDIT' '$HOME_A/.claude/CLAUDE.md' 2>/dev/null"
assert "A: got B's deploy.md" "[ -f '$HOME_A/.claude/commands/deploy.md' ]"
assert "A: got B's skill" "[ -f '$HOME_A/.claude/skills/my-skill/SKILL.md' ]"

# ==========================================================
# Step 6: Real launch (no --bare) — hook fires automatically
# ==========================================================
echo ""
echo "--- Step 6: Real launch — hook fires automatically ---"

echo "# MARKER_HOOK_TEST" >> "$HOME_A/.claude/CLAUDE.md"

run_claude "$HOME_A" \
  -- "Just say OK."

restart_claude "$HOME_B"

echo ""
assert "Hook synced: B got MARKER_HOOK_TEST" "grep -q 'MARKER_HOOK_TEST' '$HOME_B/.claude/CLAUDE.md' 2>/dev/null"

# ==========================================================
# Step 7: Conflict test
# ==========================================================
echo ""
echo "--- Step 7: Conflict resolution ---"

# A edits CLAUDE.md and pushes
echo "CONFLICT_LINE_FROM_A" > "$HOME_A/.claude/CLAUDE.md"
restart_claude "$HOME_A"

# B edits same file differently (divergent)
echo "CONFLICT_LINE_FROM_B" > "$HOME_B/.claude/CLAUDE.md"

# B's hook should hit a rebase conflict
hook_output=$(HOME="$HOME_B" bash "$HOME_B/.claude/sync-hook.sh" 2>&1) || true
dim "[hook output] $hook_output"
assert "Conflict detected by hook" "echo '$hook_output' | grep -qi 'conflict\\|rebase'"

# Claude resolves the conflict
run_claude "$HOME_B" \
  --bare \
  -- "There is a git rebase conflict in ~/.claude. Resolve it by accepting both changes, then commit and push."

echo ""
# After resolution, B should be able to push and the file should have content from both
assert "Conflict resolved: B can push" "git -C '$HOME_B/.claude' diff --quiet origin/main 2>/dev/null"
assert "Conflict resolved: file has content" "[ -s '$HOME_B/.claude/CLAUDE.md' ]"

# ==========================================================
# Step 8: Uninstall on both machines
# ==========================================================
echo ""
echo "--- Step 8: Uninstall on both machines ---"

echo "Uninstalling on Machine A..."
run_claude "$HOME_A" \
  --bare \
  -- "$UNINSTALL_PROMPT"

echo ""
echo "Uninstalling on Machine B..."
run_claude "$HOME_B" \
  --bare \
  -- "$UNINSTALL_PROMPT"

echo ""
# Verify uninstall on A
assert "A: .git removed" "[ ! -d '$HOME_A/.claude/.git' ]"
assert "A: sync-hook.sh removed" "[ ! -f '$HOME_A/.claude/sync-hook.sh' ]"
assert "A: .gitignore removed" "[ ! -f '$HOME_A/.claude/.gitignore' ]"
assert "A: CLAUDE.md preserved" "[ -f '$HOME_A/.claude/CLAUDE.md' ]"
assert "A: settings.json preserved (no hook)" "[ -f '$HOME_A/.claude/settings.json' ] && ! grep -q 'sync-hook.sh' '$HOME_A/.claude/settings.json' 2>/dev/null"

# Verify uninstall on B
assert "B: .git removed" "[ ! -d '$HOME_B/.claude/.git' ]"
assert "B: sync-hook.sh removed" "[ ! -f '$HOME_B/.claude/sync-hook.sh' ]"
assert "B: .gitignore removed" "[ ! -f '$HOME_B/.claude/.gitignore' ]"
assert "B: CLAUDE.md preserved" "[ -f '$HOME_B/.claude/CLAUDE.md' ]"
assert "B: settings.json preserved (no hook)" "[ -f '$HOME_B/.claude/settings.json' ] && ! grep -q 'sync-hook.sh' '$HOME_B/.claude/settings.json' 2>/dev/null"

# ==========================================================
# Summary
# ==========================================================
echo ""
echo "================================"
TOTAL=$((PASS+FAIL))
echo "Results: $PASS/$TOTAL passed"
if [ "$FAIL" -gt 0 ]; then red "$FAIL test(s) failed"; exit 1
else green "All tests passed!"; fi
