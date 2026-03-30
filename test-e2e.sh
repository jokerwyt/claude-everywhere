#!/bin/bash
# End-to-end test for ClaudeEverywhere config sync.
# Simulates two machines (A and B) syncing through a shared git remote.
#
# Scenario:
#   1. Create a bare "GitHub" remote seeded with ClaudeEverywhere scaffolding
#   2. Machine A: fresh clone + setup (new machine joining)
#   3. Machine B: already has ~/.claude with custom config, then joins via git init + reset
#   4. A makes changes, syncs → B syncs → verify B got A's changes
#   5. B makes changes, syncs → A syncs → verify A got B's changes
#   6. Both make non-conflicting changes simultaneously → verify merge works
#
# Usage: bash test-e2e.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_ROOT=$(mktemp -d)
REMOTE="$TEST_ROOT/remote.git"
HOME_A="$TEST_ROOT/home_a"
HOME_B="$TEST_ROOT/home_b"
PASS=0
FAIL=0

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

green() { printf "\033[32m✓ %s\033[0m\n" "$1"; }
red()   { printf "\033[31m✗ %s\033[0m\n" "$1"; }

assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then
    green "$desc"
    PASS=$((PASS + 1))
  else
    red "$desc"
    FAIL=$((FAIL + 1))
  fi
}

# --- Helpers ---

# Set up git identity for a fake HOME (required since ~/.gitconfig won't exist)
init_home() {
  local home="$1" name="$2"
  mkdir -p "$home"
  git config --file "$home/.gitconfig" user.name "Test User $name"
  git config --file "$home/.gitconfig" user.email "test-$name@example.com"
}

# Simulate Claude Code launching on a machine (runs sync-hook.sh with that HOME)
claude_launch() {
  local home="$1"
  HOME="$home" bash "$home/.claude/sync-hook.sh" 2>/dev/null
}

# Run setup.sh on a machine
run_setup() {
  local home="$1"
  HOME="$home" bash "$home/.claude/setup.sh" 2>/dev/null
}

echo "=== ClaudeEverywhere E2E Test ==="
echo "Test root: $TEST_ROOT"
echo ""

# ============================================================
# Step 0: Create bare remote, seed with repo scaffolding
# ============================================================
echo "--- Step 0: Create remote repo ---"

git init --bare "$REMOTE" >/dev/null 2>&1

# Seed remote with the repo content
seed=$(mktemp -d)
git clone "$REMOTE" "$seed/repo" >/dev/null 2>&1
cp "$REPO_DIR"/{sync-hook.sh,setup.sh,.gitignore,CLAUDE.md.example,settings.json.example} "$seed/repo/" 2>/dev/null || true
cp "$REPO_DIR/.gitignore" "$seed/repo/"
cp "$REPO_DIR/sync-hook.sh" "$seed/repo/"
cp "$REPO_DIR/setup.sh" "$seed/repo/"
(cd "$seed/repo" && git add -A && git commit -m "initial scaffolding" >/dev/null 2>&1 && git push >/dev/null 2>&1)
rm -rf "$seed"

green "Remote repo created and seeded"
echo ""

# ============================================================
# Step 1: Machine A — fresh clone + setup
# ============================================================
echo "--- Step 1: Machine A joins (fresh clone) ---"

init_home "$HOME_A" "A"
git clone "$REMOTE" "$HOME_A/.claude" >/dev/null 2>&1
run_setup "$HOME_A"

assert "A: settings.json exists" "[ -f '$HOME_A/.claude/settings.json' ]"
assert "A: SessionStart hook is configured" "grep -q 'sync-hook.sh' '$HOME_A/.claude/settings.json'"

# Sync A so its settings.json is pushed to remote before B joins
claude_launch "$HOME_A"

echo ""

# ============================================================
# Step 2: Machine B — pre-existing ~/.claude with custom config, then joins
# ============================================================
echo "--- Step 2: Machine B joins (existing config) ---"

init_home "$HOME_B" "B"
mkdir -p "$HOME_B/.claude/commands"
mkdir -p "$HOME_B/.claude/skills/my-skill"

# B already has custom CLAUDE.md
cat > "$HOME_B/.claude/CLAUDE.md" << 'BEOF'
# My Custom Config

- Always use TypeScript
- Prefer functional style

## Project Notes
Team standup at 10am daily
BEOF

# B has a custom slash command
cat > "$HOME_B/.claude/commands/deploy.md" << 'BEOF'
Deploy the current branch to staging.
Run: npm run build && npm run deploy:staging
BEOF

# B has a custom skill
cat > "$HOME_B/.claude/skills/my-skill/SKILL.md" << 'BEOF'
---
name: my-skill
description: A custom skill for testing
---
# My Skill
Does something useful.
BEOF

# B has existing settings with custom permissions
# Note: settings.json will be merged by setup.sh, and B's version will be synced.
# A will pick it up on next sync, so both machines converge.
cat > "$HOME_B/.claude/settings.json" << 'BEOF'
{
  "permissions": {
    "allow": ["bash", "read"],
    "deny": ["rm -rf /"]
  },
  "model": "opus"
}
BEOF

# B joins using the git init + reset flow (from README)
# The reset brings in remote files (including A's settings.json),
# but B's local settings.json is preserved since reset doesn't touch dirty files.
(
  cd "$HOME_B/.claude"
  git init >/dev/null 2>&1
  git remote add origin "$REMOTE" >/dev/null 2>&1
  git fetch origin >/dev/null 2>&1
  git reset origin/main >/dev/null 2>&1
  git checkout -- sync-hook.sh setup.sh .gitignore >/dev/null 2>&1
)
run_setup "$HOME_B"

# Commit and push B's existing config
(
  cd "$HOME_B/.claude"
  git add -A && git commit -m "initial sync from B" >/dev/null 2>&1
  git push -u origin main >/dev/null 2>&1
)

# A must sync now to pick up B's settings.json (and everything else),
# otherwise A's stale settings.json will conflict on next rebase.
claude_launch "$HOME_A"

assert "B: CLAUDE.md preserved" "grep -q 'Always use TypeScript' '$HOME_B/.claude/CLAUDE.md'"
assert "B: custom command preserved" "[ -f '$HOME_B/.claude/commands/deploy.md' ]"
assert "B: custom skill preserved" "[ -f '$HOME_B/.claude/skills/my-skill/SKILL.md' ]"
assert "B: existing permissions preserved" "grep -q '\"model\": \"opus\"' '$HOME_B/.claude/settings.json'"
assert "B: SessionStart hook merged in" "grep -q 'sync-hook.sh' '$HOME_B/.claude/settings.json'"

echo ""

# ============================================================
# Step 3: A syncs — should pull B's config
# ============================================================
echo "--- Step 3: A launches Claude → pulls B's config ---"

claude_launch "$HOME_A"

assert "A: got B's CLAUDE.md" "grep -q 'Always use TypeScript' '$HOME_A/.claude/CLAUDE.md'"
assert "A: got B's deploy command" "[ -f '$HOME_A/.claude/commands/deploy.md' ]"
assert "A: got B's skill" "[ -f '$HOME_A/.claude/skills/my-skill/SKILL.md' ]"

echo ""

# ============================================================
# Step 4: A adds config, syncs → B syncs → verify
# ============================================================
echo "--- Step 4: A→B sync (A adds new command) ---"

mkdir -p "$HOME_A/.claude/commands"
cat > "$HOME_A/.claude/commands/test.md" << 'AEOF'
Run the test suite: npm test
AEOF

# A also edits CLAUDE.md (appends, no conflict with B's content)
echo "" >> "$HOME_A/.claude/CLAUDE.md"
echo "## Machine A Notes" >> "$HOME_A/.claude/CLAUDE.md"
echo "- Added by machine A" >> "$HOME_A/.claude/CLAUDE.md"

claude_launch "$HOME_A"  # commits + pushes
claude_launch "$HOME_B"  # pulls

assert "B: got A's test command" "[ -f '$HOME_B/.claude/commands/test.md' ]"
assert "B: got A's CLAUDE.md edits" "grep -q 'Added by machine A' '$HOME_B/.claude/CLAUDE.md'"

echo ""

# ============================================================
# Step 5: B adds config, syncs → A syncs → verify
# ============================================================
echo "--- Step 5: B→A sync (B adds new skill) ---"

mkdir -p "$HOME_B/.claude/skills/another-skill"
cat > "$HOME_B/.claude/skills/another-skill/SKILL.md" << 'BEOF'
---
name: another-skill
description: Added by machine B
---
# Another Skill
BEOF

claude_launch "$HOME_B"  # commits + pushes
claude_launch "$HOME_A"  # pulls

assert "A: got B's new skill" "[ -f '$HOME_A/.claude/skills/another-skill/SKILL.md' ]"

echo ""

# ============================================================
# Step 6: Both make non-conflicting changes simultaneously
# ============================================================
echo "--- Step 6: Simultaneous non-conflicting edits ---"

# A edits one file
cat > "$HOME_A/.claude/commands/test.md" << 'AEOF'
Run the test suite with coverage: npm test -- --coverage
AEOF

# B adds a different file
cat > "$HOME_B/.claude/commands/lint.md" << 'BEOF'
Run the linter: npm run lint
BEOF

# A syncs first (commits + pushes)
claude_launch "$HOME_A"
# B syncs (should rebase cleanly on top of A's push)
claude_launch "$HOME_B"
# A syncs again to get B's addition
claude_launch "$HOME_A"

assert "A: has B's lint command" "[ -f '$HOME_A/.claude/commands/lint.md' ]"
assert "B: has A's updated test command" "grep -q 'coverage' '$HOME_B/.claude/commands/test.md'"
assert "A: has own updated test command" "grep -q 'coverage' '$HOME_A/.claude/commands/test.md'"
assert "B: has own lint command" "[ -f '$HOME_B/.claude/commands/lint.md' ]"

echo ""

# ============================================================
# Step 7: Verify .gitignore whitelist — untracked files stay local
# ============================================================
echo "--- Step 7: .gitignore whitelist ---"

echo "secret" > "$HOME_A/.claude/secret.env"
mkdir -p "$HOME_A/.claude/projects/myproj"
echo "local data" > "$HOME_A/.claude/projects/myproj/data.json"

claude_launch "$HOME_A"
claude_launch "$HOME_B"

assert "B: secret.env NOT synced" "[ ! -f '$HOME_B/.claude/secret.env' ]"
assert "B: projects/ NOT synced" "[ ! -d '$HOME_B/.claude/projects' ]"

echo ""

# ============================================================
# Step 8: setup.sh idempotency
# ============================================================
echo "--- Step 8: setup.sh idempotency ---"

hook_count_before=$(grep -c 'sync-hook.sh' "$HOME_A/.claude/settings.json")
run_setup "$HOME_A"
hook_count_after=$(grep -c 'sync-hook.sh' "$HOME_A/.claude/settings.json")

assert "setup.sh idempotent (hook not duplicated)" "[ '$hook_count_before' = '$hook_count_after' ]"

echo ""

# ============================================================
# Step 9: Nested directories sync (issue #5 fix)
# ============================================================
echo "--- Step 9: Recursive directory sync ---"

mkdir -p "$HOME_A/.claude/commands/sub"
echo "nested command" > "$HOME_A/.claude/commands/sub/nested.md"
mkdir -p "$HOME_A/.claude/skills/deep/nested"
echo "deep skill" > "$HOME_A/.claude/skills/deep/nested/deep.md"

claude_launch "$HOME_A"
claude_launch "$HOME_B"

assert "B: got nested command" "[ -f '$HOME_B/.claude/commands/sub/nested.md' ]"
assert "B: got deeply nested skill" "[ -f '$HOME_B/.claude/skills/deep/nested/deep.md' ]"

echo ""

# ============================================================
# Summary
# ============================================================
echo "================================"
TOTAL=$((PASS + FAIL))
echo "Results: $PASS/$TOTAL passed"
if [ "$FAIL" -gt 0 ]; then
  red "$FAIL test(s) failed"
  exit 1
else
  green "All tests passed!"
  exit 0
fi
