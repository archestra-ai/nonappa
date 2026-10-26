#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
swift scripts/update-key.swift generate "$FIXTURE/private" "$FIXTURE/public"
swift scripts/update-key.swift verify "$FIXTURE/private" "$FIXTURE/public"
export SPARKLE_PUBLIC_ED_KEY
SPARKLE_PUBLIC_ED_KEY=$(cat "$FIXTURE/public")
bash scripts/package.sh
VERSION=$(tr -d '\r\n' < version.txt)
ARCHIVE="$ROOT/build/release/NoNappa-$VERSION-universal.zip"
SIGNER="$ROOT/build/dependencies/sparkle/bin/sign_update"
SIGNATURE=$("$SIGNER" --ed-key-file "$FIXTURE/private" -p "$ARCHIVE")
"$SIGNER" --verify --ed-key-file "$FIXTURE/private" "$ARCHIVE" "$SIGNATURE"
python3 scripts/make-appcast.py "$ARCHIVE" "$VERSION" "$SIGNATURE" "$FIXTURE/appcast.xml"
ditto -x -k "$ARCHIVE" "$FIXTURE/unpacked"
APP="$FIXTURE/unpacked/NoNappa.app"
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/NoNappa" --check-runtime
for executable in MacOS/NoNappa Helpers/NoNappaHelper; do
  lipo "$APP/Contents/$executable" -verify_arch arm64 x86_64
done
python3 - "$FIXTURE" "$VERSION" <<'PY'
import base64
import plistlib
import runpy
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

fixture, version = Path(sys.argv[1]), sys.argv[2]
plist = plistlib.loads((fixture / 'unpacked/NoNappa.app/Contents/Info.plist').read_bytes())
assert plist['CFBundleShortVersionString'] == plist['CFBundleVersion'] == version
assert plist['SUPublicEDKey'] == (fixture / 'public').read_text()
assert plist['SUFeedURL'] == 'https://github.com/archestra-ai/nonappa/releases/latest/download/appcast.xml'
feed = ET.parse(fixture / 'appcast.xml')
item = feed.find('channel/item')
assert item.find('{http://www.andymatuschak.org/xml-namespaces/sparkle}version').text == version
archive = Path(f'build/release/NoNappa-{version}-universal.zip')
assert int(item.find('enclosure').attrib['length']) == archive.stat().st_size
assert item.find('enclosure').attrib['url'].endswith(f'/v{version}/{archive.name}')
make = runpy.run_path('scripts/make-appcast.py')['make_appcast']
for invalid in ['-1', '../1.0.0', '1.0.0; echo bad', '1.0.0-beta']:
    try:
        make(archive, invalid, base64.b64encode(bytes(64)).decode())
    except ValueError:
        pass
    else:
        raise AssertionError('invalid version accepted')
for invalid in ['', 'not-a-signature', base64.b64encode(bytes(32)).decode()]:
    try:
        make(archive, version, invalid)
    except ValueError:
        pass
    else:
        raise AssertionError('invalid signature accepted')
PY
cp "$ARCHIVE" "$FIXTURE/tampered.zip"
printf x >> "$FIXTURE/tampered.zip"
if "$SIGNER" --verify --ed-key-file "$FIXTURE/private" "$FIXTURE/tampered.zip" "$SIGNATURE"; then
  echo 'Tampered archive unexpectedly verified' >&2
  exit 1
fi
printf 'Passed: runtime launch, universal packaged app/helper, embedded version and public key, appcast metadata, Sparkle signatures, malformed inputs, tampered-archive rejection.\n'
