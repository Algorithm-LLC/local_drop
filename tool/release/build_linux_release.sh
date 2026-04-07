#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

ARTIFACT_DIR="$ROOT/build/release-artifacts/linux"
STAGE_DIR="$ARTIFACT_DIR/LocalDrop"
mkdir -p "$ARTIFACT_DIR"

FLUTTER_ARGS=()
if [[ -n "${LOCALDROP_BUILD_NAME:-}" ]]; then
  FLUTTER_ARGS+=("--build-name=$LOCALDROP_BUILD_NAME")
fi
if [[ -n "${LOCALDROP_BUILD_NUMBER:-}" ]]; then
  FLUTTER_ARGS+=("--build-number=$LOCALDROP_BUILD_NUMBER")
fi

flutter build linux --release "${FLUTTER_ARGS[@]}"

RELEASE_DIR="$ROOT/build/linux/x64/release/bundle"
if [[ ! -d "$RELEASE_DIR" ]]; then
  echo "Linux release output was not found at $RELEASE_DIR" >&2
  exit 1
fi

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$RELEASE_DIR"/. "$STAGE_DIR"/

tar -czf "$ARTIFACT_DIR/LocalDrop-linux-release.tar.gz" -C "$ARTIFACT_DIR" LocalDrop

if command -v appimagetool >/dev/null 2>&1; then
  echo "appimagetool detected. Add your AppDir layout here if you want a signed AppImage."
else
  echo "appimagetool not found; tar.gz artifact created and AppImage packaging skipped."
fi

echo "Linux artifacts are ready in $ARTIFACT_DIR"
