#!/bin/bash
START_TIME=$SECONDS
INTERNAL_TIMEOUT=15
cd ~/.claude || exit 0

# Lock: prevent concurrent runs (two Claude sessions starting simultaneously)
LOCKFILE=~/.claude/.sync-lock
if [ -f "$LOCKFILE" ]; then
  lock_age=$(( $(date +%s) - $(stat -f %m "$LOCKFILE" 2>/dev/null || stat -c %Y "$LOCKFILE" 2>/dev/null || echo 0) ))
  if [ "$lock_age" -lt 60 ]; then
    echo '{"systemMessage":"[claude-everywhere] Sync already running, skipped."}'
    exit 0
  fi
  # Stale lock (>60s), remove it
fi
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"; git rebase --abort >/dev/null 2>&1; echo "{\"systemMessage\":\"⚠ Config sync timed out, skipped.\"}"; exit 0' TERM
trap 'rm -f "$LOCKFILE"' EXIT

# Portable timeout: macOS lacks coreutils `timeout`, try gtimeout, else skip
run_with_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$INTERNAL_TIMEOUT" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$INTERNAL_TIMEOUT" "$@"
  else
    "$@"
  fi
  local rc=$?
  if [ $rc -eq 124 ]; then
    SUMMARY="${SUMMARY}⚠ '${*}' timed out (>${INTERNAL_TIMEOUT}s). "
    return 1
  fi
  return $rc
}

SUMMARY=""
DIFF=""

# 1. Commit local changes
git add -A 2>/dev/null
if ! git diff --cached --quiet 2>/dev/null; then
  COMMITTED=$(git diff --cached --name-only 2>/dev/null)
  git commit -m "auto-sync $(hostname -s) $(date '+%Y-%m-%d %H:%M')" >/dev/null 2>&1
  SUMMARY="Committed: ${COMMITTED//$'\n'/, }. "
fi

# 2. Pull remote
OLD_HEAD=$(git rev-parse HEAD 2>/dev/null)
if run_with_timeout git pull --rebase --autostash >/dev/null 2>&1; then
  # Check for autostash pop conflicts
  if git diff --name-only --diff-filter=U 2>/dev/null | grep -q .; then
    SUMMARY="${SUMMARY}⚠ Autostash conflict — run: cd ~/.claude && git stash show. "
  fi
  NEW_HEAD=$(git rev-parse HEAD 2>/dev/null)
  if [ "$OLD_HEAD" != "$NEW_HEAD" ]; then
    PULLED=$(git diff --name-only "$OLD_HEAD" "$NEW_HEAD" 2>/dev/null)
    DIFF=$(git diff --stat "$OLD_HEAD" "$NEW_HEAD" 2>/dev/null)
    SUMMARY="${SUMMARY}Pulled: ${PULLED//$'\n'/, }. "
  fi
  run_with_timeout git push >/dev/null 2>&1 || {
    # Push failed (e.g., remote updated between pull and push). Retry once.
    if run_with_timeout git pull --rebase --autostash >/dev/null 2>&1; then
      run_with_timeout git push >/dev/null 2>&1 || {
        SUMMARY="${SUMMARY}⚠ Push failed after retry. "
      }
    else
      git rebase --abort >/dev/null 2>&1
      SUMMARY="${SUMMARY}⚠ Push retry conflict! Run: cd ~/.claude && git pull --rebase to resolve. "
    fi
  }
else
  git rebase --abort >/dev/null 2>&1
  # Only add conflict message if not already a timeout message
  if [[ "$SUMMARY" != *"timed out"* ]]; then
    SUMMARY="${SUMMARY}⚠ Rebase conflict! Run: cd ~/.claude && git pull --rebase to resolve."
  fi
fi

# Output
if [ -z "$SUMMARY" ]; then
  SUMMARY="No changes."
fi

ELAPSED=$(( SECONDS - START_TIME ))
SUMMARY="${SUMMARY}(${ELAPSED}s)"

# Escape for JSON
SUMMARY=$(printf '%s' "$SUMMARY" | sed 's/\\/\\\\/g; s/"/\\"/g')
DIFF_ESC=$(printf '%s' "$DIFF" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed '$ s/\\n$//')

# systemMessage: shown to user; additionalContext: injected into Claude's context
if [ -n "$DIFF_ESC" ]; then
  echo "{\"systemMessage\":\"[claude-everywhere]${SUMMARY}\",\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"Config sync result: ${SUMMARY}\\nDiff:\\n${DIFF_ESC}\"}}"
else
  echo "{\"systemMessage\":\"[claude-everywhere]${SUMMARY}\",\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"Config sync result: ${SUMMARY}\"}}"
fi
