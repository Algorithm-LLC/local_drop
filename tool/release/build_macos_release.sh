#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

ARTIFACT_DIR="$ROOT/build/release-artifacts/macos"
STAGE_DIR="$ARTIFACT_DIR/LocalDrop"
mkdir -p "$ARTIFACT_DIR"

FLUTTER_ARGS=()
if [[ -n "${LOCALDROP_BUILD_NAME:-}" ]]; then
  FLUTTER_ARGS+=("--build-name=$LOCALDROP_BUILD_NAME")
fi
if [[ -n "${LOCALDROP_BUILD_NUMBER:-}" ]]; then
  FLUTTER_ARGS+=("--build-number=$LOCALDROP_BUILD_NUMBER")
fi

flutter build macos --release "${FLUTTER_ARGS[@]}"

APP_PATH="$ROOT/build/macos/Build/Products/Release/LocalDrop.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "macOS release output was not found at $APP_PATH" >&2
  exit 1
fi

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR"/

if [[ -n "${LOCALDROP_MACOS_CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --sign "$LOCALDROP_MACOS_CODESIGN_IDENTITY" "$STAGE_DIR/LocalDrop.app"
fi

ditto -c -k --sequesterRsrc --keepParent "$STAGE_DIR/LocalDrop.app" "$ARTIFACT_DIR/LocalDrop-macos-release.zip"

if command -v hdiutil >/dev/null 2>&1; then
  hdiutil create -volname "LocalDrop" -srcfolder "$STAGE_DIR" -ov -format UDZO "$ARTIFACT_DIR/LocalDrop-macos-release.dmg"
  if [[ -n "${LOCALDROP_MACOS_NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$ARTIFACT_DIR/LocalDrop-macos-release.dmg" --keychain-profile "$LOCALDROP_MACOS_NOTARY_PROFILE" --wait
  fi
fi

echo "macOS artifacts are ready in $ARTIFACT_DIR"
