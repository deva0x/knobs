#!/usr/bin/env bash
# Builds a release DMG of Knobs on this Mac. There is no hosted CI or release pipeline (DEC-002).
#   scripts/release.sh 0.1.0
# 1. Runs scripts/ci.sh release, which also builds the app in Release.
# 2. Copies that app into a staging folder.
# 3. With a "Developer ID Application" certificate: signs the app with the hardened runtime, notarizes it with
#    the `knobs-notary` keychain profile and staples the ticket. Without one, it builds an unsigned DMG and says so.
# 4. Builds the DMG with diskutil (the app plus an Applications link), and signs, notarizes and staples it too when it can.
# 5. Writes dist/Knobs-<version>.dmg and its SHA-256.
# 6. When everything is signed and notarized, adds the DMG to Sparkle's feed, website/appcast.xml, signed with
#    Knobs' EdDSA key from the keychain (DEC-024), fills in the Homebrew cask (DEC-025), and prints the
#    `gh release create` command for Deva.
#    It never runs that command, never deploys the website and never pushes.
set -euo pipefail

notary_profile="knobs-notary"
# The keychain account holding Knobs' EdDSA key, made once with `generate_keys --account knobs`.
sparkle_account="knobs"
sparkle_bin="build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
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
# The website's download links name this release's files, listed in the page's #release: its version first, then
# each file name.
website_release=$(python3 -I - website/index.html <<'PY'
import json, re, sys
page = open(sys.argv[1], encoding="utf-8").read()
release = json.loads(re.search(r'<script type="application/json" id="release">(.*?)</script>', page, re.S).group(1))
print(release["version"])
print(release["mac"])
for distro in release["linux"]:
    print(*distro["files"].values(), sep="\n")
PY
)
if [ "$(head -1 <<<"$website_release")" != "$version" ]; then
    echo "FAIL: website/index.html's #release is for version $(head -1 <<<"$website_release"), not $version." >&2
    echo "Update its version and file names first." >&2
    exit 1
fi
# Sparkle installs only an update signed by the key whose public half the running app carries.
if ! grep -q '^ *SUPublicEDKey: "[A-Za-z0-9+/]\{43\}="$' project.yml; then
    echo "FAIL: project.yml has no SUPublicEDKey, so this release could never be updated. See docs/WORKFLOW.md," >&2
    echo "Releasing, for the one-time generate_keys step." >&2
    exit 1
fi
# Sparkle orders updates by CFBundleVersion, not by the version people see.
build_number=$(sed -n 's/^ *CFBundleVersion: "\(.*\)"$/\1/p' project.yml)
if [ -f website/appcast.xml ]; then
    newest_build=$(python3 -I - website/appcast.xml <<'PY'
import sys, xml.etree.ElementTree as ET
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
items = ET.parse(sys.argv[1]).getroot().iter("item")
print(max(int(item.find(SPARKLE + "version").text) for item in items))
PY
)
    if [ "$build_number" -le "$newest_build" ]; then
        echo "FAIL: project.yml's CFBundleVersion is $build_number, but website/appcast.xml already lists build" >&2
        echo "$newest_build. Raise CFBundleVersion first." >&2
        exit 1
    fi
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
    sign() { codesign --force --options runtime --timestamp --sign "$identity" "$@"; }
    # Sparkle's helpers first, in the order Sparkle's documentation gives, then the app. Never --deep: the
    # Downloader keeps entitlements of its own.
    sparkle="$staging/Knobs.app/Contents/Frameworks/Sparkle.framework"
    sign "$sparkle/Versions/B/XPCServices/Installer.xpc"
    sign --preserve-metadata=entitlements "$sparkle/Versions/B/XPCServices/Downloader.xpc"
    sign "$sparkle/Versions/B/Autoupdate"
    sign "$sparkle/Versions/B/Updater.app"
    sign "$sparkle"
    sign "$staging/Knobs.app"
    codesign --verify --deep --strict --verbose=2 "$staging/Knobs.app"

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
# Publishing without a file the website links to would leave a download button that leads nowhere.
missing=""
while read -r file; do
    [ -f "dist/$file" ] || [ -f "dist/linux/$file" ] || missing="$missing $file"
done < <(tail -n +2 <<<"$website_release")
if [ -n "$missing" ]; then
    echo
    echo "NOT READY: the website links to files that aren't in dist/ yet:$missing" >&2
    echo "Build the Linux ones with scripts/linux.sh package $version arm64 and amd64, then run this again." >&2
    exit 1
fi

step "Add the DMG to Sparkle's feed"
# generate_appcast reuses the appcast in the folder it is given and moves files it calls old, so it gets a folder
# of its own: the current feed, this DMG, and this version's changelog section as the update window's notes. The
# keychain may ask to let it use the key.
feed=$(mktemp -d build/appcast.XXXXXX)
if [ -f website/appcast.xml ]; then cp website/appcast.xml "$feed/"; fi
cp "$dmg" "$feed/"
python3 -I - CHANGELOG.md "$version" >"$feed/Knobs-$version.md" <<'PY'
import re, sys
changelog, version = open(sys.argv[1], encoding="utf-8").read(), sys.argv[2]
print(re.search(r"^## \[" + re.escape(version) + r"\].*?\n(.*?)(?=^## \[|\Z)", changelog, re.S | re.M).group(1).strip())
PY
"$sparkle_bin/generate_appcast" --account "$sparkle_account" --embed-release-notes --link https://knobs.pages.dev \
    --download-url-prefix "https://github.com/deva0x/knobs/releases/download/v$version/" "$feed"
# A key that doesn't match the app's SUPublicEDKey is only a warning to generate_appcast; it then leaves the
# update unsigned, and every copy of Knobs would refuse it.
if ! python3 -I - "$feed/appcast.xml" "$build_number" <<'PY'; then
import sys, xml.etree.ElementTree as ET
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
for item in ET.parse(sys.argv[1]).getroot().iter("item"):
    if item.find(SPARKLE + "version").text == sys.argv[2]:
        sys.exit(0 if item.find("enclosure").get(SPARKLE + "edSignature") else 1)
sys.exit(1)
PY
    echo "FAIL: the feed has no signed entry for build $build_number. Check the generate_appcast warnings above." >&2
    exit 1
fi
cp "$feed/appcast.xml" website/appcast.xml
echo "website/appcast.xml now offers $version."

step "Fill in the Homebrew cask"
# For the deva0x/homebrew-knobs tap (DEC-025), without the template's own comment.
mkdir -p dist/homebrew
sed -e '/^#/d' -e "s/@VERSION@/$version/" -e "s/@SHA256@/$(cut -d' ' -f1 "dist/Knobs-$version.dmg.sha256")/" \
    scripts/homebrew/knobs.rb >dist/homebrew/knobs.rb
echo "dist/homebrew/knobs.rb is the cask for $version."

echo
echo "When Deva approves publishing, Deva runs:"
# The Linux packages of the same version, from `scripts/linux.sh package`, go up beside the DMG.
linux_files=""
for file in dist/linux/*"$version"*; do
    [ -f "$file" ] && linux_files="$linux_files '$file'"
done
echo "  gh release create v$version '$dmg' 'dist/Knobs-$version.dmg.sha256'$linux_files --title 'Knobs $version' --notes-file <notes>"
echo "Only after that release exists: commit website/appcast.xml and deploy website/, and put dist/homebrew/knobs.rb"
echo "in the tap as Casks/knobs.rb, so the feed, the download buttons and the cask never point at files that aren't"
echo "there yet (docs/WORKFLOW.md, Releasing)."
