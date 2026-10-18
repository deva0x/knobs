#!/usr/bin/env bash
# Lays out the installed files under a staging root, the same for the .deb and the .rpm. Runs in a build
# container with the repo at /knobs. Usage: stage.sh <built binary> <staging root> <version>
set -euo pipefail
binary=$1
stage=$2
version=$3
repo=/knobs
here=$repo/linux/packaging

install -Dm755 "$binary" "$stage/usr/bin/knobs"
strip "$stage/usr/bin/knobs"
install -d "$stage/usr/share/knobs/manifests"
install -m644 "$repo"/Manifests/*.json "$stage/usr/share/knobs/manifests/"
install -Dm644 "$here/io.github.deva0x.Knobs.desktop" "$stage/usr/share/applications/io.github.deva0x.Knobs.desktop"
install -d "$stage/usr/share/metainfo"
sed -e "s/@VERSION@/$version/" -e "s/@DATE@/$(date -u +%F)/" "$here/io.github.deva0x.Knobs.metainfo.xml" \
    >"$stage/usr/share/metainfo/io.github.deva0x.Knobs.metainfo.xml"
for size in 256 512; do
    install -Dm644 "$here/icons/$size.png" "$stage/usr/share/icons/hicolor/${size}x${size}/apps/io.github.deva0x.Knobs.png"
done
install -Dm644 "$repo/LICENSE" "$stage/usr/share/licenses/knobs/LICENSE"
