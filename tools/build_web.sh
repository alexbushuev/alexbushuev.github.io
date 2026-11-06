#!/bin/bash
# Exports the browser build and packs it for the server: gzipped wasm and pck, manifest with sizes and hashes.
set -e
GODOT="$1"; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; DIST="$ROOT/dist"
cd "$ROOT"
rm -rf build/web/*; mkdir -p build/web
"$GODOT" --headless --path . --export-release "Web" build/web/index.html 2>&1 | grep -E 'ERROR|SCRIPT ERROR' | grep -vE 'audio|ALSA' || true
rm -rf "$DIST"; mkdir -p "$DIST"; touch "$DIST/.gdignore"
BUILD=$(cat build/web/index.pck | sha256sum | cut -c1-10)
for f in build/web/*; do
  b=$(basename "$f")
  case "$b" in
    *.wasm|*.pck) gzip -9 -c "$f" > "$DIST/$b.gz" ;;
    index.html) sed "s/__BUILD__/$BUILD/g" "$f" > "$DIST/index.html" ;;
    *.import) ;;
    *) cp "$f" "$DIST/$b" ;;
  esac
done
rm -f "$DIST/.gdignore"
( cd "$DIST" && for f in *; do echo "$(sha256sum "$f" | cut -d' ' -f1) $(stat -c %s "$f") $f"; done ) > "$ROOT/build/manifest.txt"
mv "$ROOT/build/manifest.txt" "$DIST/manifest.txt"
touch "$ROOT/dist/.gdignore"
echo "build $BUILD"; ls -la "$DIST" | awk 'NR>3{printf "%10d %s\n",$5,$9}'
du -sh "$DIST" | cut -f1
