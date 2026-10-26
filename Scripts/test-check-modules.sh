#!/bin/bash
# Checks Scripts/check-modules.sh itself: the real tree passes, and a copy with one import
# breaking each rule is refused with exactly those violations.
set -uo pipefail
cd "$(dirname "$0")/.."

fail() { echo "check-modules self-test: $1" >&2; exit 1; }

Scripts/check-modules.sh >/dev/null || fail "the real Sources tree was refused"

tree="$(mktemp -d)"
trap 'rm -rf "$tree"' EXIT
cp -R Sources "$tree/Sources"
add() { echo "import $2" > "$tree/Sources/$1/BoundaryProbe.swift"; }
add TimerFeature MediaFeature    # a Feature using another Feature
add TimerCore SwiftUI            # a Core with an interface
add MediaCore Cocoa              # Cocoa brings AppKit in
add NotchCore AppKit             # the platform's logic is pure
add NotchShell ClipboardCore     # the platform knows no feature
add aranotch-hook NotchCore      # a tool uses its own feature's Core only
add ClipboardMCP AgentCore       # … not another feature's

out="$(Scripts/check-modules.sh "$tree/Sources" 2>/dev/null)"
code=$?
[[ $code -eq 1 ]] || fail "a tree with violations exited $code"
for expected in "TimerFeature: imports MediaFeature" "TimerCore: imports SwiftUI" "MediaCore: imports Cocoa" \
    "NotchCore: imports AppKit" "NotchShell: imports ClipboardCore" "aranotch-hook: imports NotchCore" \
    "ClipboardMCP: imports AgentCore"; do
    grep -q "^$expected " <<<"$out" || fail "missed '$expected'. Got:
$out"
done
count="$(grep -c ' imports ' <<<"$out")"
[[ $count -eq 7 ]] || fail "expected 7 violations, got $count:
$out"
echo "check-modules self-test passed"
