#!/bin/bash
# Puts dist/ into the gaz3d branch as one single commit. Old builds are dropped, so the repository does not grow.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
MSG="$(printf 'Газ и цепь 3D: сборка %s\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01Ws84sjLD3e4E37f1D8qwmx\n' "$(sha256sum dist/index.html | cut -c1-8)")"
TREE=$(cd dist && for f in *; do printf '100644 blob %s\t%s\n' "$(git -C "$ROOT" hash-object -w "$f")" "$f"; done | git -C "$ROOT" mktree)
COMMIT=$(git commit-tree "$TREE" -m "$MSG")
git push -f origin "$COMMIT:refs/heads/gaz3d" 2>&1 | tail -1
echo "pushed gaz3d $COMMIT"
