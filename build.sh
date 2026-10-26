#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/build"
APP="$OUT/NoNappa.app"
SPARKLE=$(bash "$ROOT/scripts/fetch-sparkle.sh")
VERSION=$(tr -d '\r\n' < "$ROOT/version.txt")
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid version.txt" >&2; exit 1; }
IDENTITY=${CODE_SIGN_IDENTITY:--}
ARCH=${TARGET_ARCH:-$(uname -m)}
SIGN_ARGS=(--force --options runtime --sign "$IDENTITY")
UPDATER_FLAGS=(-Xlinker -rpath -Xlinker @executable_path/../Frameworks)
if [[ "$IDENTITY" != - ]]; then
  SIGN_ARGS+=(--timestamp)
  UPDATER_FLAGS+=(-F "$SPARKLE" -framework Sparkle)
fi
# Check the production updater API even when building an ad-hoc developer binary.
xcrun swiftc -typecheck -parse-as-library -target "$ARCH-apple-macosx13.0" \
  "$ROOT/Sources/Core.swift" "$ROOT/Sources/HelperProtocol.swift" "$ROOT/Sources/HelperClient.swift" \
  "$ROOT/Sources/Updates.swift" "$ROOT/Sources/App.swift" -F "$SPARKLE" -framework Sparkle
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
xcrun swiftc -O -parse-as-library -target "$ARCH-apple-macosx13.0" \
  "$ROOT/Sources/Core.swift" "$ROOT/Sources/HelperProtocol.swift" "$ROOT/Sources/Helper.swift" -o "$APP/Contents/Helpers/NoNappaHelper"
codesign "${SIGN_ARGS[@]}" "$APP/Contents/Helpers/NoNappaHelper"
xcrun swiftc -O -parse-as-library -target "$ARCH-apple-macosx13.0" \
  "$ROOT/Sources/Core.swift" "$ROOT/Sources/HelperProtocol.swift" "$ROOT/Sources/HelperClient.swift" "$ROOT/Sources/Updates.swift" "$ROOT/Sources/App.swift" \
  "${UPDATER_FLAGS[@]}" -o "$APP/Contents/MacOS/NoNappa"
cp "$SPARKLE/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE"
cp "$ROOT/Resources/mark.json" "$ROOT/Resources/openappa.svg" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>NoNappa</string>
<key>CFBundleIdentifier</key><string>com.nonappa.app</string>
<key>CFBundleName</key><string>NoNappa</string>
<key>CFBundleDisplayName</key><string>NoNappa</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
if [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string https://github.com/archestra-ai/nonappa/releases/latest/download/appcast.xml" "$APP/Contents/Info.plist"
fi
# Hardened ad-hoc binaries have no Team ID and cannot load third-party dylibs.
# Keep library validation intact; only embed Sparkle in Developer ID builds.
rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
if [[ "$IDENTITY" != - ]]; then
  mkdir -p "$APP/Contents/Frameworks"
  ditto "$SPARKLE/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
  FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  for nested in "$FRAMEWORK/XPCServices/Downloader.xpc" "$FRAMEWORK/XPCServices/Installer.xpc" "$FRAMEWORK/Updater.app" "$FRAMEWORK/Autoupdate"; do
    codesign "${SIGN_ARGS[@]}" --preserve-metadata=entitlements "$nested"
  done
  codesign "${SIGN_ARGS[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
fi
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built %s\n' "$APP"
if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  ditto "$APP" "$HOME/Applications/NoNappa.app"
  open "$HOME/Applications/NoNappa.app"
fi
