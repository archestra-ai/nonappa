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
xcrun swiftc -parse-as-library -D NONAPPA_MODEL_TESTS -target "$(uname -m)-apple-macosx13.0" \
  "$ROOT/Sources/Core.swift" "$ROOT/Sources/HelperProtocol.swift" "$ROOT/Sources/HelperClient.swift" \
  "$ROOT/Sources/App.swift" "$ROOT/Tests/ModelTests.swift" -o "$ROOT/build/model-tests"
"$ROOT/build/model-tests"
