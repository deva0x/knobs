#!/usr/bin/env bash
# Local CI for Knobs. There is no hosted CI for this repo (DEC-002); this script is the only gate.
#   scripts/ci.sh fast     no-hosted-CI check, format lint, core unit tests (pre-commit)
#   scripts/ci.sh          fast + integration tests + Debug app build (pre-push, milestone checks)
#   scripts/ci.sh release  full + Release app build; integration tests fail instead of skip when a tool is missing
#   scripts/ci.sh linux    format lint, then every library built and the core unit tests run on Linux, in a
#                          local container (OrbStack or Docker on this Mac, never a hosted runner).
#                          KNOBS_LINUX_IMAGE picks the image.
set -euo pipefail

mode="${1:-full}"
case "$mode" in fast | full | release | linux) ;; *) echo "usage: scripts/ci.sh [fast|release|linux]" >&2; exit 64 ;; esac
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

if [ "$mode" = linux ]; then
    # The oldest Swift that Package.swift allows, on the current Ubuntu LTS.
    image="${KNOBS_LINUX_IMAGE:-swift:6.2-noble}"
    step "Core unit tests on Linux ($image)"
    if ! command -v docker >/dev/null || ! docker info >/dev/null 2>&1; then
        echo "FAIL: no local Docker. Start OrbStack (or Docker Desktop) and run this again." >&2
        exit 1
    fi
    # The sources go in on stdin rather than a bind mount, which OrbStack doesn't share for every folder.
    # Manifests are included because the tests load the real ones. --init puts a reaper at PID 1, as systemd is
    # on a desktop, so the tools that cancel kills don't linger as zombies the tests would count as running.
    tar -cf - Package.swift Sources Tests Manifests |
        docker run --rm -i --init "$image" bash -c \
            'mkdir /src && cd /src && tar -xf - &&
             swift build -Xswiftc -warnings-as-errors &&
             swift test -Xswiftc -warnings-as-errors --skip IntegrationTests'
    printf '\nci.sh linux: PASS\n'
    exit 0
fi

if [ "$mode" = fast ]; then
    step "Core unit tests"
    # Warnings fail here too, as they do in the app build, so the commit hook catches them.
    swift test -Xswiftc -warnings-as-errors --skip IntegrationTests
    printf '\nci.sh fast: PASS\n'
    exit 0
fi

step "Core unit and integration tests"
if [ "$mode" = release ]; then export KNOBS_REQUIRE_TOOLS=1; fi
swift test -Xswiftc -warnings-as-errors

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
