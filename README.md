# Knobs

Knobs gives command-line tools a Mac window. Pick a tool and a task ("Shrink a video"), drop in a file,
set a few plain controls, and press Run. The exact command is always shown, so you can see and learn
what's happening.

Status: in development, working toward v0.1.0. See [docs/PLAN.md](docs/PLAN.md).

## Tools in the first release

ffmpeg, yt-dlp, ImageMagick, pandoc, exiftool, ocrmypdf, Ghostscript, whisper.cpp, rsync, 7-Zip.
Knobs doesn't install tools. If one is missing, it shows the `brew install` command to copy.

Each tool is described by a JSON manifest in [Manifests/](Manifests/). The format is documented in
[docs/MANIFEST_FORMAT.md](docs/MANIFEST_FORMAT.md), so adding a tool needs no Swift code.

## Building

Requires macOS 15 or later on Apple Silicon, Xcode 26 or later, and XcodeGen (`brew install xcodegen`).

```bash
scripts/install-hooks.sh
scripts/ci.sh
scripts/run-app.sh
```

All checks run locally. This project uses no hosted CI.

## License

MIT. See [LICENSE](LICENSE).
