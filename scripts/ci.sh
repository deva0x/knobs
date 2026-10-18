#!/usr/bin/env bash
# Local CI for Knobs. There is no hosted CI for this repo (DEC-002); this script is the only gate.
#   scripts/ci.sh fast     no-hosted-CI check, format lint, core unit tests (pre-commit)
#   scripts/ci.sh          fast + integration tests + Debug app build (pre-push, milestone checks)
#   scripts/ci.sh release  full + Release app build; integration tests fail instead of skip when a tool is missing
set -euo pipefail

mode="${1:-full}"
case "$mode" in fast | full | release) ;; *) echo "usage: scripts/ci.sh [fast|release]" >&2; exit 64 ;; esac
cd "$(dirname "$0")/.."

step() { printf '\n==> %s\n' "$1"; }

step "No hosted CI"
if [ -d .github/workflows ]; then
    echo "FAIL: .github/workflows exists. Hosted CI is forbidden in this repo (DEC-002)." >&2
    exit 1
fi
echo "ok"

step "Format lint"
xcrun swift-format lint --strict --recursive Package.swift Sources Tests App
echo "ok"

if [ "$mode" = fast ]; then
    step "Core unit tests"
    swift test --skip IntegrationTests
    printf '\nci.sh fast: PASS\n'
    exit 0
fi

step "Core unit and integration tests"
if [ "$mode" = release ]; then export KNOBS_REQUIRE_TOOLS=1; fi
swift test

build_app() {
    xcodebuild -project Knobs.xcodeproj -scheme Knobs -configuration "$1" \
        -derivedDataPath build/DerivedData -quiet \
        SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES \
        build
}

step "Generate Xcode project"
xcodegen generate --quiet

step "App build (Debug)"
build_app Debug
echo "ok"

if [ "$mode" = release ]; then
    step "App build (Release)"
    build_app Release
    echo "ok"
fi

printf '\nci.sh %s: PASS\n' "$mode"
