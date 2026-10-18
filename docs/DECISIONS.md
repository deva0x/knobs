# Decisions

One entry per decision. Never delete one. When a decision changes, add a new entry that supersedes it
and mark the old one "Superseded by DEC-NNN".

## DEC-001: Build Knobs, a Mac app that turns command-line tools into windows (2026-10-18)
Deva chose this from a shortlist of open-source ideas checked against existing projects. Native,
manifest-driven Mac apps for arbitrary command-line tools didn't exist: there were only research prototypes,
Python-only and Rust-only generators, and Windows tools. First release: ffmpeg, yt-dlp, ImageMagick,
pandoc, exiftool, ocrmypdf, Ghostscript, whisper.cpp, rsync and 7-Zip (fixed by Deva).

## DEC-002: No hosted CI, everything local (2026-10-18)
Deva lost about $250 on GitHub Actions. All CI and releases run on the Mac through `scripts/`. See WORKFLOW.

## DEC-003: Direct download with Developer ID, not the Mac App Store (2026-10-18)
Knobs launches binaries the user installed with Homebrew. The App Store sandbox forbids that, so the app
can't be sandboxed. It ships as a notarized DMG signed with Developer ID, with hardened runtime on.

## DEC-004: Manifests are JSON in a documented schema (2026-10-18)
JSON decodes with Swift's built-in `Codable`, so no YAML dependency is needed. The format is in
`docs/MANIFEST_FORMAT.md`. Manifests are the extension surface: adding a tool never needs Swift code.

## DEC-005: Swift 6, SwiftUI, macOS 15 and later, Apple Silicon (2026-10-18). Deployment target superseded by DEC-012
macOS 15 reaches most current Macs while allowing modern SwiftUI. It's built with Xcode 27 on macOS 27.
Intel isn't supported in v0.1.0 because Homebrew paths and testing are Apple Silicon only.

## DEC-006: Tools run as an argv array, never a shell string (2026-10-18)
`ToolRunner` uses `Process` with `executableURL` and `arguments`. The command preview is a display
rendering of that argv, quoted for reading and copying, and it's never executed. This makes shell
injection through file names or field values impossible.

## DEC-007: Code layout: a Swift package core plus an XcodeGen app (2026-10-18)
`KnobsCore` (manifests, command building, running, presets, help parsing) is a Swift package tested with
`swift test`, so it's fast and needs no UI. The app target is described in `project.yml` and generated with
XcodeGen. The `.xcodeproj` is generated output and isn't committed, which avoids project-file merge
problems.

## DEC-008: One formatter: swift-format from the toolchain (2026-10-18)
It ships with Xcode, so there's nothing to install. Configuration is in `.swift-format`. SwiftLint is
installed on this Mac but isn't used, to keep one way of doing things.

## DEC-009: Allowed downloads for development (2026-10-18, approved by Deva; model location changed by DEC-013)
- Homebrew formulas for the 10 tools: ffmpeg, yt-dlp, imagemagick, pandoc, exiftool, ocrmypdf,
  ghostscript, whisper-cpp, rsync, sevenzip.
- One whisper.cpp model for tests: `ggml-tiny.en.bin` (about 75 MB) from the whisper.cpp model repository
  on Hugging Face, stored outside the repo in `~/Library/Caches/knobs-dev/`.

## DEC-010: Name "Knobs", the MIT license and bundle id `io.github.deva0x.Knobs` are working choices (2026-10-18, pending Deva)
Both can change until the first public release (PLAN M10).

## DEC-011: Three layers per tool: tasks, extra arguments, all options (2026-10-18)
Deva asked whether every option of tools like ffmpeg would be included. Showing every option would be as
intimidating as the Terminal and impossible to maintain. So each tool gets curated everyday tasks (5 to 6
for the big three, 3 to 4 for the rest), every task gets an "Extra arguments" box, and every tool gets a
generated "All options" view from its help text. Deva approved this for all tools.

## DEC-012: Deployment target macOS 26 (2026-10-18). Supersedes the macOS 15 target in DEC-005
Deva asked for a very premium app with new, modern UI. macOS 26 brings the Liquid Glass design language and
its SwiftUI APIs. macOS 27 is current, so macOS 26 and later still covers most active Macs. Apple Silicon
only, as in DEC-005.

## DEC-013: Standing authorization and boundaries (2026-10-18)
Deva's words: work without stopping for anything that needs Deva, with permission to do anything except
obviously risky things such as `rm`, and touch nothing outside this project folder. In practice:
- Allowed: create, edit and commit files inside the repo; install the DEC-009 Homebrew formulas (part of
  the approved plan; Homebrew is the one place outside the folder that the plan needs); build and launch the
  app; use design tools and skills; preview the website locally.
- The whisper test model goes inside the repo at `.cache/models/` (gitignored), not in `~/Library`.
- Not allowed: deleting anything outside the repo, `sudo`, pushing, creating remote repos, publishing
  releases or websites, changing GitHub or system settings, or entering credentials.
- Questions go under "Waiting on Deva" in STATUS, and work continues on everything else.
