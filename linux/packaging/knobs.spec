# Packs the files scripts/linux.sh staged in Fedora into an RPM; it compiles nothing itself.
# Requires are found automatically from the binary's shared libraries (GTK 4, libadwaita and so on).
Name:           knobs
Version:        @VERSION@
Release:        1%{?dist}
Summary:        Command-line tools, as simple windows
License:        MIT
URL:            https://github.com/deva0x/knobs
# The tools Knobs drives; each is optional, and Knobs says when one is missing.
Recommends:     ffmpeg-free yt-dlp ImageMagick pandoc perl-Image-ExifTool ocrmypdf ghostscript rsync 7zip

%description
Knobs puts the everyday jobs of ffmpeg, yt-dlp, ImageMagick, pandoc and other command-line tools behind
plain controls, and always shows the exact command it runs.

%install
cp -a %{_sourcedir}/stage/. %{buildroot}/

%files
%{_bindir}/knobs
%{_datadir}/knobs
%{_datadir}/applications/io.github.deva0x.Knobs.desktop
%{_datadir}/metainfo/io.github.deva0x.Knobs.metainfo.xml
%{_datadir}/icons/hicolor/256x256/apps/io.github.deva0x.Knobs.png
%{_datadir}/icons/hicolor/512x512/apps/io.github.deva0x.Knobs.png
%license %{_datadir}/licenses/knobs/LICENSE
