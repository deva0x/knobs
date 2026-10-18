#!/usr/bin/env bash
# Builds the Arch package in the Arch container from the tarball package-tarball.sh made.
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
su builder -c "cd '$work' && makepkg --nodeps --noconfirm"
mkdir -p "$out"
cp "$work"/knobs-bin-*.pkg.tar.zst "$out/"
