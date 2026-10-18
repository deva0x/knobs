#!/usr/bin/env bash
# Builds the .deb in the Ubuntu container. Usage: package-deb.sh <built binary> <version> <output folder>
set -euo pipefail
binary=$1
version=$2
out=$3
work=$(mktemp -d)
stage=$work/knobs
/knobs/linux/packaging/stage.sh "$binary" "$stage" "$version"
# Debian keeps the license as the package's copyright file.
install -Dm644 /knobs/LICENSE "$stage/usr/share/doc/knobs/copyright"
rm -r "$stage/usr/share/licenses"

# dpkg-shlibdeps turns the binary's shared libraries into package dependencies; it reads debian/control.
mkdir -p "$work/debian" "$stage/DEBIAN"
printf 'Source: knobs\n\nPackage: knobs\nArchitecture: any\n' >"$work/debian/control"
depends=$(cd "$work" && dpkg-shlibdeps -O "$stage/usr/bin/knobs" | sed -n 's/^shlibs:Depends=//p')
arch=$(dpkg --print-architecture)
cat >"$stage/DEBIAN/control" <<CONTROL
Package: knobs
Version: $version
Architecture: $arch
Maintainer: Devaprasad T P
Depends: $depends
Recommends: ffmpeg, yt-dlp, imagemagick, pandoc, libimage-exiftool-perl, ocrmypdf, ghostscript, rsync, 7zip, whisper.cpp
Section: utils
Priority: optional
Homepage: https://github.com/deva0x/knobs
Description: Command-line tools, as simple windows
 Knobs puts the everyday jobs of ffmpeg, yt-dlp, ImageMagick, pandoc and other
 command-line tools behind plain controls, and always shows the exact command.
CONTROL
mkdir -p "$out"
dpkg-deb --root-owner-group --build "$stage" "$out/knobs_${version}_${arch}.deb"
