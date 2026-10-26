#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/build/dependencies/sparkle"
VERSION=2.10.1
SHA=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
ARCHIVE="$ROOT/build/dependencies/Sparkle-$VERSION.tar.xz"
mkdir -p "$(dirname "$ARCHIVE")"
if [[ ! -f "$ARCHIVE" ]]; then
  curl --fail --location --retry 3 "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz" -o "$ARCHIVE.download"
  mv "$ARCHIVE.download" "$ARCHIVE"
fi
printf '%s  %s\n' "$SHA" "$ARCHIVE" | shasum -a 256 -c - >&2
if [[ ! -f "$DEST/.verified-$SHA" ]]; then
  rm -rf "$DEST"
  mkdir -p "$DEST"
  tar -xf "$ARCHIVE" -C "$DEST"
  touch "$DEST/.verified-$SHA"
fi
printf '%s\n' "$DEST"
