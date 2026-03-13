#!/bin/bash
set -euo pipefail

SAVE_REASON="${1:-MANUAL}"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

echo ""
echo "=========================================="
echo "💾 SAVING WORLD - $SAVE_REASON"
echo "=========================================="

# ensure we run from repo root if this is a git repo, otherwise use current dir
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
cd "$REPO_ROOT"

SUSPENDED_SAVE=0

# If server.stdin named pipe exists, pause server autosaves to avoid race conditions
if [ -p server.stdin ]; then
echo "❗ Asking server to pause saves..."
echo "save-off" > server.stdin   # stop autosaves
# flush the world to disk
echo "save-all" > server.stdin
sleep 2
SUSPENDED_SAVE=1
else
echo "⚠️ server.stdin pipe not found; proceeding without save lock"
fi

# Stage everything (recursive). -A covers additions, modifications and deletions.
git add -A

# If nothing staged -> show debug info and exit cleanly
if git diff --staged --quiet; then
echo "ℹ️ No staged changes detected."

echo ""
echo "---- git status (porcelain) ----"
git status --porcelain || true

echo "---- Untracked (not ignored) ----"
git ls-files -o --exclude-standard || true

echo "---- Top-level .gitignore (if present) ----"
[ -f .gitignore ] && sed -n '1,200p' .gitignore || echo "(no .gitignore)"

# Re-enable saving if we paused it
if [ "$SUSPENDED_SAVE" -eq 1 ]; then
echo "save-on" > server.stdin
echo "✅ Server saves re-enabled"
fi

echo "✅ Nothing to commit"
exit 0
fi

COMMIT_MSG="Auto-save: $SAVE_REASON at $TIMESTAMP [skip ci]"

if git commit -m "$COMMIT_MSG"; then
echo "✅ Committed changes: $COMMIT_MSG"
else
echo "❌ Commit failed. Showing git status:"
git status || true
# re-enable saving before exiting
if [ "$SUSPENDED_SAVE" -eq 1 ]; then
echo "save-on" > server.stdin
fi
exit 1
fi

# Pull with rebase to reduce merge commits; if it fails we still try to push (will fail on conflicts)
set +e
git pull --rebase origin main
PULL_RC=$?
set -e

if [ $PULL_RC -ne 0 ]; then
echo "⚠️ git pull returned non-zero ($PULL_RC). There may be remote changes. Attempting to push anyway."
fi

if git push origin main; then
echo "✅ Changes pushed to repository"
else
echo "❌ git push failed. Showing remote info:"
git remote -v || true
# re-enable saving before exit
if [ "$SUSPENDED_SAVE" -eq 1 ]; then
echo "save-on" > server.stdin
fi
exit 1
fi

# Re-enable server saving if we paused it
if [ "$SUSPENDED_SAVE" -eq 1 ]; then
echo "save-on" > server.stdin
echo "✅ Server saves re-enabled"
fi

echo "✅ Save completed"
