#!/usr/bin/env bash
# Builds a release DMG of Knobs on this Mac. There is no hosted CI or release pipeline (DEC-002).
#   scripts/release.sh 0.1.0
# 1. Runs scripts/ci.sh release, which also builds the app in Release.
# 2. Copies that app into a staging folder.
# 3. With a "Developer ID Application" certificate: signs the app with the hardened runtime, notarizes it with
#    the `knobs-notary` keychain profile and staples the ticket. Without one, it builds an unsigned DMG and says so.
# 4. Builds the DMG with diskutil (the app plus an Applications link), and signs, notarizes and staples it too when it can.
# 5. Writes dist/Knobs-<version>.dmg and its SHA-256, and prints the `gh release create` command for Deva.
#    It never runs that command and never pushes.
set -euo pipefail

notary_profile="knobs-notary"
version="${1:-}"
cd "$(dirname "$0")/.."

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "usage: scripts/release.sh <version>, for example scripts/release.sh 0.1.0" >&2
    exit 64
fi
project_version=$(sed -n 's/^ *CFBundleShortVersionString: "\(.*\)"$/\1/p' project.yml)
if [ "$version" != "$project_version" ]; then
    echo "FAIL: project.yml says version $project_version, not $version. Update CFBundleShortVersionString first." >&2
    exit 1
fi
if ! grep -q "^## \[$version\]" CHANGELOG.md; then
    echo "FAIL: CHANGELOG.md has no '## [$version]' section." >&2
    exit 1
fi

step() { printf '\n==> %s\n' "$1"; }

step "Local CI (release mode), which also builds the Release app"
scripts/ci.sh release
app="build/DerivedData/Build/Products/Release/Knobs.app"

mkdir -p dist
staging=$(mktemp -d build/dmg.XXXXXX)
ditto "$app" "$staging/Knobs.app"
ln -s /Applications "$staging/Applications"
dmg="dist/Knobs-$version.dmg"

identity=$(security find-identity -v -p codesigning |
    sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -n 1)
can_notarize=no
if [ -n "$identity" ] && xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1; then
    can_notarize=yes
fi

notarize() {
    xcrun notarytool submit "$1" --keychain-profile "$notary_profile" --wait
}

if [ -n "$identity" ]; then
    step "Sign the app ($identity)"
    codesign --force --options runtime --timestamp --sign "$identity" "$staging/Knobs.app"
    codesign --verify --strict --verbose=2 "$staging/Knobs.app"

    if [ "$can_notarize" = yes ]; then
        step "Notarize the app"
        zip="$staging.zip"
        ditto -c -k --keepParent "$staging/Knobs.app" "$zip"
        notarize "$zip"
        xcrun stapler staple "$staging/Knobs.app"
    fi
fi

step "Build the DMG"
# diskutil replaces the deprecated `hdiutil create`; it overwrites an existing image at the same path.
diskutil image create from --format UDZO --volumeName "Knobs $version" "$staging" "$dmg" >/dev/null

if [ -n "$identity" ]; then
    codesign --force --timestamp --sign "$identity" "$dmg"
    if [ "$can_notarize" = yes ]; then
        step "Notarize the DMG"
        notarize "$dmg"
        xcrun stapler staple "$dmg"
        spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
    fi
fi

(cd dist && shasum -a 256 "Knobs-$version.dmg" >"Knobs-$version.dmg.sha256")

step "Done"
echo "DMG:      $dmg"
echo "SHA-256:  $(cut -d' ' -f1 "dist/Knobs-$version.dmg.sha256")"
if [ -z "$identity" ]; then
    echo
    echo "UNSIGNED: no 'Developer ID Application' certificate in the keychain. Gatekeeper will block this DMG."
    echo "Create one in Xcode → Settings → Accounts → Manage Certificates, then run this script again."
    exit 0
fi
if [ "$can_notarize" = no ]; then
    echo
    echo "NOT NOTARIZED: the '$notary_profile' keychain profile is missing. See docs/WORKFLOW.md, Releasing."
    exit 0
fi
echo
echo "When Deva approves publishing, Deva runs:"
echo "  gh release create v$version '$dmg' 'dist/Knobs-$version.dmg.sha256' --title 'Knobs $version' --notes-file <notes>"
