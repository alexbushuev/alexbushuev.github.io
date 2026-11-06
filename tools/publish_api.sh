#!/bin/bash
# Publishes the server to the gaz-api branch: one commit with gaz_api.py, setup.sh and a manifest of sha256 sums.
# The server's updater pulls it from there every 5 minutes.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
python3 -m py_compile server/gaz_api.py
bash -n server/setup.sh
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cp server/gaz_api.py server/setup.sh "$TMP/"
( cd "$TMP" && for f in gaz_api.py setup.sh; do echo "$(sha256sum "$f" | cut -d' ' -f1) $(stat -c %s "$f") $f"; done > manifest.txt )
export GIT_INDEX_FILE="$TMP/index"
git read-tree --empty
for f in gaz_api.py setup.sh manifest.txt; do
  h=$(git hash-object -w "$TMP/$f")
  mode=100644; [ "$f" = setup.sh ] && mode=100755
  git update-index --add --cacheinfo $mode,$h,$f
done
tree=$(git write-tree)
c=$(printf 'Сервер аккаунтов и рекордов\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01Ws84sjLD3e4E37f1D8qwmx\n' | git commit-tree "$tree")
git push -q -f origin "$c:refs/heads/gaz-api"
echo "pushed gaz-api $c"
