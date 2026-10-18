#!/usr/bin/env bash
# Builds the Debug app and opens it for a screenshot review: project-local data folder, no animations, and the
# given appearance. Usage: scripts/review-app.sh [light|dark] [file to open...]
set -euo pipefail
cd "$(dirname "$0")/.."
appearance="${1:-dark}"
shift || true
xcodegen generate --quiet
xcodebuild -project Knobs.xcodeproj -scheme Knobs -configuration Debug -derivedDataPath build/DerivedData -quiet build
pkill -x Knobs || true
sleep 1
app="$PWD/build/DerivedData/Build/Products/Debug/Knobs.app"
open -n "$app" --args -KnobsDataDirectory "$PWD/.cache/appdata" -KnobsDisableAnimations YES -KnobsAppearance "$appearance"
if [ "$#" -gt 0 ]; then
    sleep 2
    open -a "$app" "$@"
fi
