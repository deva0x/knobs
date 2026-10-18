#!/usr/bin/env bash
# Lays out the .deb's files and control file in the Ubuntu container of the package's architecture, where
# dpkg-shlibdeps can see that architecture's libraries. scripts/linux.sh then packs <stage folder> with dpkg-deb
# in a native container: under emulation, tar can't read the file list dpkg-deb gives it.
# Usage: package-deb.sh <built binary> <version> <stage folder, new and empty>
set -euo pipefail
binary=$1
version=$2
stage=$3
work=$(mktemp -d)
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
