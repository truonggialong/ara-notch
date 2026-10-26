#!/bin/bash
# Checks the module boundaries, then runs the test suite. Extra arguments are passed to `swift test`.
#
# With only the Command Line Tools installed (no Xcode), incremental test builds
# fail to resolve the Swift Testing macro plugin; loading it explicitly avoids that.
set -euo pipefail
cd "$(dirname "$0")/.."

Scripts/check-modules.sh
Scripts/test-check-modules.sh >/dev/null

PLUGIN="/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
ARGS=()
if [[ "$(xcode-select -p 2>/dev/null)" == "/Library/Developer/CommandLineTools" && -f "$PLUGIN" ]]; then
    ARGS+=(-Xswiftc -load-plugin-library -Xswiftc "$PLUGIN")
fi

exec swift test "${ARGS[@]}" "$@"
