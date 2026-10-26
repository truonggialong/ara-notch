#!/bin/bash
# Runs one module's tests, after checking the module boundaries. Run Scripts/test.sh afterwards
# for the whole suite before calling a fix done (docs/modules/README.md).
# Usage: Scripts/test-module.sh <Module>
set -euo pipefail
cd "$(dirname "$0")/.."

MODULES="Platform App Clipboard Calendar Media Timer Agent Files Capture Translate Windows SystemEvents Overview Tools"
module="${1:-}"

case "$module" in
    Platform) suites="NotchCoreTests|NotchShellTests" ;;
    Clipboard) suites="ClipboardCoreTests|ClipboardFeatureTests|ClipboardMCPTests" ;;
    Agent) suites="AgentCoreTests|AgentFeatureTests" ;;
    Capture) suites="CaptureCoreTests|CaptureFeatureTests" ;;
    Calendar | Media | Timer | Files | Translate | Windows | SystemEvents) suites="${module}CoreTests" ;;
    Overview) suites="OverviewCoreTests|OverviewFeatureTests" ;;
    Tools) suites="ToolsFeatureTests" ;;
    App) suites="" ;;
    *)
        echo "Unknown module '$module'. One of: $MODULES" >&2
        exit 2
        ;;
esac

Scripts/check-modules.sh
if [[ -z "$suites" ]]; then
    echo "$module has no tests of its own: build the app and try it by hand, then run Scripts/test.sh."
    exit 0
fi
exec Scripts/test.sh --filter "^($suites)\."
