#!/usr/bin/env bash
# Packs the staged files into knobs-<version>-linux-<arch>.tar.gz, the source of the Arch package.
# Runs in the Ubuntu container. Usage: package-tarball.sh <built binary> <version> <output folder>
set -euo pipefail
binary=$1
version=$2
out=$3
work=$(mktemp -d)
/knobs/linux/packaging/stage.sh "$binary" "$work/knobs" "$version"
mkdir -p "$out"
tar -C "$work" --owner=0 --group=0 -czf "$out/knobs-$version-linux-$(uname -m).tar.gz" knobs
