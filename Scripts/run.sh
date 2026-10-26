#!/bin/bash
# Rebuilds and relaunches the app. Extra arguments are passed to AraNotch.
set -euo pipefail
cd "$(dirname "$0")/.."

pkill -x AraNotch || true
Scripts/build-app.sh debug
open build/AraNotch.app --args "$@"
