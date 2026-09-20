#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/build"
APP="$OUT/NoNappa.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
xcrun swiftc -O -parse-as-library -target "$(uname -m)-apple-macosx13.0" \
  "$ROOT/Sources/Core.swift" "$ROOT/Sources/HelperProtocol.swift" "$ROOT/Sources/Helper.swift" -o "$APP/Contents/Helpers/NoNappaHelper"
codesign --force --options runtime --sign - "$APP/Contents/Helpers/NoNappaHelper"
xcrun swiftc -O -parse-as-library -target "$(uname -m)-apple-macosx13.0" \
  "$ROOT/Sources/Core.swift" "$ROOT/Sources/HelperProtocol.swift" "$ROOT/Sources/HelperClient.swift" "$ROOT/Sources/App.swift" -o "$APP/Contents/MacOS/NoNappa"
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
codesign --force --options runtime --sign - "$APP"
printf 'Built %s\n' "$APP"
if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  ditto "$APP" "$HOME/Applications/NoNappa.app"
  open "$HOME/Applications/NoNappa.app"
fi
