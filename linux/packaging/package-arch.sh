#!/usr/bin/env bash
# Builds the Arch package in the Arch container from the tarball package-tarball.sh made, and writes the
# PKGBUILD and .SRCINFO to publish on the AUR to <output folder>/aur/. Push those only after the GitHub release
# holds the tarball: the AUR's PKGBUILD downloads it from there.
# Usage: package-arch.sh <tarball> <version> <output folder>
set -euo pipefail
tarball=$1
version=$2
out=$3
work=$(mktemp -d)
cp "$tarball" "$work/"
checksum=$(sha256sum "$tarball" | cut -d' ' -f1)
sed -e "s/@VERSION@/$version/" -e "s/@SHA256@/$checksum/" /knobs/linux/packaging/PKGBUILD >"$work/PKGBUILD"
chown -R builder "$work"
su builder -c "cd '$work' && makepkg --nodeps --noconfirm && makepkg --printsrcinfo >.SRCINFO"
mkdir -p "$out/aur"
cp "$work"/knobs-gui-bin-*.pkg.tar.zst "$out/"
cp "$work/PKGBUILD" "$work/.SRCINFO" "$out/aur/"
