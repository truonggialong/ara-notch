#!/bin/bash
# Checks Scripts/check-modules.sh itself: the real tree passes, and a copy with one import
# breaking each rule is refused with exactly those violations.
set -uo pipefail
cd "$(dirname "$0")/.."

fail() { echo "check-modules self-test: $1" >&2; exit 1; }

Scripts/check-modules.sh >/dev/null || fail "the real tree was refused"

tree="$(mktemp -d)"
trap 'rm -rf "$tree"' EXIT
cp -R App Modules "$tree/"
add() { echo "import $2" > "$tree/Modules/$1/BoundaryProbe.swift"; }
add Timer/Feature MediaFeature          # a Feature using another Feature
add Timer/Core SwiftUI                  # a Core with an interface
add Media/Core Cocoa                    # Cocoa brings AppKit in
add Platform/NotchCore AppKit           # the platform's logic is pure
add Platform/NotchShell ClipboardCore   # the platform knows no feature
add Agent/aranotch-hook NotchCore       # a tool uses its own feature's Core only
add Clipboard/MCP AgentCore             # … not another feature's
# Imports written other ways count the same: indented under a condition, one declaration, a submodule.
printf '#if canImport(AppKit)\n    import AppKit\n#endif\n' > "$tree/Modules/Files/Core/BoundaryProbe.swift"
echo "import struct CalendarCore.CalendarEvent" > "$tree/Modules/Windows/Feature/BoundaryProbe.swift"
echo "@_exported import MediaFeature.Lyrics" > "$tree/Modules/SystemEvents/Feature/BoundaryProbe.swift"

out="$(Scripts/check-modules.sh "$tree" 2>/dev/null)"
code=$?
[[ $code -eq 1 ]] || fail "a tree with violations exited $code"
for expected in "TimerFeature: imports MediaFeature" "TimerCore: imports SwiftUI" "MediaCore: imports Cocoa" \
    "NotchCore: imports AppKit" "NotchShell: imports ClipboardCore" "aranotch-hook: imports NotchCore" \
    "ClipboardMCP: imports AgentCore" "FilesCore: imports AppKit" "WindowsFeature: imports CalendarCore" \
    "SystemEventsFeature: imports MediaFeature"; do
    grep -q "^$expected " <<<"$out" || fail "missed '$expected'. Got:
$out"
done
count="$(grep -c ' imports ' <<<"$out")"
[[ $count -eq 10 ]] || fail "expected 10 violations, got $count:
$out"
echo "check-modules self-test passed"
