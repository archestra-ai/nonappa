#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/NoNappa.app"
IDENTITY=${CODE_SIGN_IDENTITY:--}
for arch in arm64 x86_64; do
  TARGET_ARCH=$arch bash "$ROOT/build.sh"
  mkdir -p "$ROOT/build/slices/$arch"
  cp "$APP/Contents/MacOS/NoNappa" "$ROOT/build/slices/$arch/NoNappa"
  cp "$APP/Contents/Helpers/NoNappaHelper" "$ROOT/build/slices/$arch/NoNappaHelper"
done
for entry in MacOS/NoNappa Helpers/NoNappaHelper; do
  name=${entry##*/}
  lipo -create "$ROOT/build/slices/arm64/$name" "$ROOT/build/slices/x86_64/$name" -output "$APP/Contents/$entry"
done
SIGN_ARGS=(--force --options runtime --sign "$IDENTITY")
if [[ "$IDENTITY" != - ]]; then SIGN_ARGS+=(--timestamp); fi
codesign "${SIGN_ARGS[@]}" "$APP/Contents/Helpers/NoNappaHelper"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
VERSION=$(tr -d '\r\n' < "$ROOT/version.txt")
mkdir -p "$ROOT/build/release"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/build/release/NoNappa-$VERSION-universal.zip"
