#!/usr/bin/env bash
# Builds the Debug app and opens it.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project Knobs.xcodeproj -scheme Knobs -configuration Debug -derivedDataPath build/DerivedData -quiet build
open build/DerivedData/Build/Products/Debug/Knobs.app
