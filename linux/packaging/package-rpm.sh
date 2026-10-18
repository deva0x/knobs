#!/usr/bin/env bash
# Builds the .rpm in the Fedora container. Usage: package-rpm.sh <built binary> <version> <output folder>
set -euo pipefail
binary=$1
version=$2
out=$3
top=$(mktemp -d)
mkdir -p "$top/SOURCES" "$top/SPECS"
/knobs/linux/packaging/stage.sh "$binary" "$top/SOURCES/stage" "$version"
sed "s/@VERSION@/$version/" /knobs/linux/packaging/knobs.spec >"$top/SPECS/knobs.spec"
rpmbuild --define "_topdir $top" -bb "$top/SPECS/knobs.spec"
mkdir -p "$out"
cp "$top"/RPMS/*/knobs-*.rpm "$out/"
