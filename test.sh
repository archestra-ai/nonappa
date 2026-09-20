#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ROOT/build"
xcrun swiftc -parse-as-library "$ROOT/Sources/Core.swift" "$ROOT/Tests/CoreTests.swift" -o "$ROOT/build/core-tests"
"$ROOT/build/core-tests"
bash "$ROOT/build.sh"
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macosx13.0" \
  "$ROOT/Sources/Core.swift" "$ROOT/Sources/HelperProtocol.swift" "$ROOT/Sources/HelperClient.swift" \
  "$ROOT/Tests/HelperTests.swift" -o "$ROOT/build/helper-tests"
"$ROOT/build/helper-tests" "$ROOT/build/NoNappa.app"
