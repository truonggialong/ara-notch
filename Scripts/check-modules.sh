#!/bin/bash
# Checks that every module imports only what its place allows (Modules/README.md):
#   <X>Core      no interface framework (SwiftUI, AppKit, Cocoa) and no NotchShell; of the
#                app's own modules only NotchCore
#   <X>Feature   of the app's own modules only <X>Core, NotchCore and NotchShell
#   NotchCore    no interface framework and none of the app's own modules
#   NotchShell   of the app's own modules only NotchCore
#   tools        only their own feature's modules: ClipboardMCP and aranotch-mcp the
#                clipboard's Core (and ClipboardMCP), aranotch-hook the agents' Core
#   AraNotch     anything: it puts the modules together
# Prints one line per import that breaks a rule and exits 1; exits 0 when there is none.
# Usage: Scripts/check-modules.sh [root]   (default: the repository; reads <root>/App and <root>/Modules)
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="${1:-.}"

# "<directory> <target>" for every module of the app: App/Sources is AraNotch; in Modules/<X>/,
# Core, Feature and MCP are <X>Core, <X>Feature and <X>MCP, and any other folder but Tests is a
# target of that name (NotchCore, NotchShell, aranotch-mcp, aranotch-hook).
targets() {
    echo "$ROOT/App/Sources AraNotch"
    for dir in "$ROOT"/Modules/*/*/; do
        dir="${dir%/}"
        part="$(basename "$dir")"
        feature="$(basename "$(dirname "$dir")")"
        case "$part" in
            Tests) ;;
            Core | Feature | MCP) echo "$dir $feature$part" ;;
            *) echo "$dir $part" ;;
        esac
    done
}

# The app's own modules.
OWN=" $(targets | awk '{print $2}' | tr '\n' ' ') "
is_own() { [[ "$OWN" == *" $1 "* ]]; }
# Frameworks that draw: none of them belongs in pure logic.
is_interface() { [[ "$1" == SwiftUI || "$1" == SwiftUICore || "$1" == AppKit || "$1" == Cocoa ]]; }

violations=0
report() {
    echo "$1: imports $2 ($3)"
    violations=$((violations + 1))
}

while read -r dir target; do
    # Every way an import is written: indented (under #if), with attributes, of one declaration
    # (`import struct M.Type`) or of a submodule (`import M.Sub`); the module is the first name.
    imports="$(grep -rhoE '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?[A-Za-z_][A-Za-z0-9_.]*' "$dir" --include='*.swift' \
        | awk '{print $NF}' | cut -d. -f1 | sort -u)"
    for module in $imports; do
        case "$target" in
            AraNotch)
                ;;
            NotchCore)
                if is_interface "$module"; then
                    report "$target" "$module" "the platform's logic has no interface"
                elif is_own "$module"; then
                    report "$target" "$module" "the platform knows no feature"
                fi
                ;;
            NotchShell)
                if is_own "$module" && [[ "$module" != NotchCore ]]; then
                    report "$target" "$module" "the platform knows no feature"
                fi
                ;;
            ClipboardMCP | aranotch-mcp)
                if is_own "$module" && [[ "$module" != ClipboardCore && "$module" != ClipboardMCP ]]; then
                    report "$target" "$module" "a tool uses its own feature's Core only"
                fi
                ;;
            aranotch-hook)
                if is_own "$module" && [[ "$module" != AgentCore ]]; then
                    report "$target" "$module" "a tool uses its own feature's Core only"
                fi
                ;;
            *Core)
                if is_interface "$module" || [[ "$module" == NotchShell ]]; then
                    report "$target" "$module" "a Core module has no interface"
                elif is_own "$module" && [[ "$module" != NotchCore ]]; then
                    report "$target" "$module" "a Core module uses only NotchCore"
                fi
                ;;
            *Feature)
                feature="${target%Feature}"
                if is_own "$module" && [[ "$module" != "${feature}Core" && "$module" != NotchCore && "$module" != NotchShell ]]; then
                    report "$target" "$module" "a Feature uses only its own Core and the platform"
                fi
                ;;
            *)
                report "$target" "$module" "unknown kind of module: add it to Scripts/check-modules.sh"
                ;;
        esac
    done
done < <(targets)

if [[ $violations -gt 0 ]]; then
    echo "$violations import(s) cross a module boundary. See Modules/README.md." >&2
    exit 1
fi
