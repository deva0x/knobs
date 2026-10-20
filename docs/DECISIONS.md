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
- Added 2026-10-20, when Deva asked for the PDF tools: qpdf, poppler (for pdftoppm and pdftotext) and img2pdf.
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

## DEC-014: Linux version in Swift with GTK 4 and libadwaita (2026-10-18, chosen by Deva)
Deva asked for the same app on popular Linux distributions and chose Swift with GTK 4 and libadwaita over
other toolkits, so the Linux app reuses `KnobsCore` and `KnobsSession` unchanged and only its windows differ.
- UI library: Adwaita for Swift, from its current home `codeberg.org/aparoksha/adwaita-swift` (the GitHub
  repository was archived in 2024-10). It has no tags after 0.1.0, so `linux/Package.swift` pins a commit, and
  `linux/Package.resolved` is committed because three of its dependencies follow a branch. It is a
  single-maintainer project; if it stalls, the C-interop route to GTK is the fallback (untested).
- It needs Swift 6.3+ and GTK 4.20+ with a matching libadwaita, so the Linux app lives in its own package,
  `linux/`, at tools version 6.3, while the shared packages stay at 6.2.
- Builds and tries run only in a local container on this Mac (`scripts/linux.sh`, image from
  `linux/Dockerfile`, Swift 6.4 on Ubuntu 26.04), never on a hosted runner (DEC-002).
- Linux-only fix found on the way: BUG-010 (Cancel and the signal mask).

## DEC-015: Linux packages are .deb and .rpm for Ubuntu 26.04+ and Fedora 43+; AppImage is held (2026-10-18, pending Deva)
Deva picked "AppImage + .deb + .rpm", which was my recommendation before the Linux spike. The spike then
showed that the UI library needs GTK 4.20+, which only Ubuntu 26.04, Fedora 43 and newer ship. That rules out
Ubuntu 24.04 LTS and Debian 13, and it clashes with AppImage, which is built on an old system and would have
to carry GTK itself. So, until Deva decides:
- Built: .deb (Ubuntu 26.04 and later) and .rpm (Fedora 43 and later), relying on the system's GTK.
- Held: AppImage.
- The open question for Deva: accept that floor, or un-defer Flatpak (GNOME runtime), the one route with this
  toolkit that reaches Ubuntu 24.04, Debian 13 and older distributions too.

## DEC-016: A tool may be installed under other names; Knobs shows the name it runs (2026-10-18)
Ubuntu 26.04's `7zip` package installs 7-Zip as `7z` (a wrapper over 7-Zip 26), not `7zz` as Homebrew does, so
Knobs reported 7-Zip as not installed. Manifests gain an optional ordered `alternativeExecutables` list. At
launch `ToolLocator.resolve` gives each manifest the first of its names that is installed, preferred name
first, and everything after that, including the command shown and copied, uses that name. Considered and
rejected: a per-platform name map (the difference follows the package, not the operating system) and
showing the preferred name while running another (the screen must show the command that runs).
Limits: names are resolved once at launch, so a tool installed later under an alternative name is found on
the next launch. Ubuntu's `7z` is the same 7-Zip as `7zz`; an old p7zip `7z` elsewhere is untested with the
7-Zip tasks.

## DEC-017: An Arch Linux package, from the Ubuntu-built binary (2026-10-18, chosen by Deva)
Deva has an Omarchy (Arch) machine and asked for an Arch package. Arch has no Swift toolchain in its official
repositories, so `knobs-bin` follows the AUR "-bin" pattern: its PKGBUILD installs the x86_64 binary built in the
Ubuntu container (Swift's runtime linked in) and depends on Arch's own gtk4 and libadwaita. Arch publishes x86_64
images only, so the package comes with `scripts/linux.sh package <version> amd64`. Publishing to the AUR is
Deva's call (it needs an AUR account and a public download for the tarball).
Its name became `knobs-gui-bin` in DEC-019.

## DEC-018: Release decisions taken on Deva's go-ahead (2026-10-19)
Deva asked for everything to be finished and said I could make the decisions. Taken, with the reason:
- Name, license, bundle id: Knobs, MIT, `io.github.deva0x.Knobs` on both platforms, as already used in the app,
  the packages, the About window and the website. If the public repository ends up under another owner, the
  id and the `github.com/deva0x/knobs` links change together before the first public release.
- Linux floor (closes DEC-015): accept GTK 4.20, so Ubuntu 26.04+, Fedora 43+ and Arch. AppImage is dropped: it
  would have to carry GTK and libadwaita itself. Flatpak stays deferred until someone needs an older LTS.
- Fedora's ffmpeg (closes BUG-012): Shrink a video asks for the H.264 codec rather than libx264, so it works with
  Fedora's own ffmpeg-free; Quality only takes effect where libx264 exists.
- Website hosting: Cloudflare Pages by direct upload from this Mac (`npx wrangler pages deploy website
  --project-name knobs`, see WORKFLOW). It needs no hosted CI; GitHub Pages publishing from a branch runs on
  GitHub Actions, which this project never uses. Deploying is publishing, so Deva runs it with their own login.
- Package maintainer contact: the name plus the project's homepage, no personal email address in published
  packages; bug reports go to the repository's issues.
Still Deva's, because they need Deva's accounts or publish something: the Developer ID certificate and notary
profile, creating and pushing the GitHub repository, deploying the website, and publishing `knobs-bin` to
the AUR.

## DEC-019: On the AUR, the Arch package is `knobs-gui-bin` (2026-10-20, chosen by Deva)
Deva said yes to publishing the Arch package on the AUR. The AUR already has `knobs`, an unrelated program by
another maintainer (system clock frequencies and power limits) that also installs `/usr/bin/knobs`. There, a
`knobs-bin` reads as a prebuilt build of that program, and its `provides=('knobs')` would claim to stand in for
it. Deva chose `knobs-gui-bin`: it provides `knobs-gui` and conflicts with `knobs` (the same `/usr/bin/knobs`)
and with 0.1.0's `knobs-bin`. Its PKGBUILD downloads the x86_64 tarball from the GitHub release, so the AUR
files go up only after the release; a local build copies the tarball in first, so nothing is downloaded. The
0.1.0 release keeps its `knobs-bin` file, which the website links to; the website changes with the next release.

## DEC-020: Agents may push `main` and the AUR package (2026-10-20, chosen by Deva)
Deva asked agents to do the publishing steps themselves instead of handing them back, and chose to let agents
push. CLAUDE.md's standing authorization now allows a plain `git push` of `main` to `origin` and a push of the
AUR files to `knobs-gui-bin`'s `master` once the release they download exists. `.claude/hooks/guard.sh` no
longer blocks a push that names `main` or `master`. Force pushes, `--no-verify`, `gh repo create` and
`gh release create` stay blocked or forbidden, and the pre-push hook still runs `scripts/ci.sh` before each push.

## DEC-021: An output can be a new folder that Knobs makes (2026-10-21, chosen by Deva)
pdftoppm writes every page as `<name>-1.png`, `<name>-2.png` and so on, can't make a folder, and replaces files of
those names. Deva chose to keep the "Nothing is overwritten" promise rather than list an exception under
SECURITY.md's Known limits. A manifest's `output` may say `"newFolder": true`: the name is picked like any output's
(an existing folder gets " 2"), and the shared run path in KnobsSession makes the folder, empty, just before the
tool starts. Intermediate folders are off, so a missing parent or a folder that appeared since the name was
picked stops the run with a message instead of mixing files in. After a failed or cancelled run Knobs removes the
folder only if it is still empty (`rmdir`, which can't remove anything inside); pages a tool already wrote are
kept. The result card shows the folder as it shows 7-Zip's extracted folder.

## DEC-022: Tell the user when a run ends while they're elsewhere (2026-10-21, chosen by Deva)
Deva picked "Done notification" for 0.2.0. On the Mac, when a run ends and Knobs isn't the active app, Knobs posts
a notification with the task's title and the result's name, or says the tool stopped with an error; clicking it
brings Knobs forward on that task. Cancelled runs aren't announced. Knobs asks macOS for permission the first time
a run ends in the background, the first moment a notification is useful, rather than at launch. A denied or
withdrawn permission is respected and only logged. While a running task reports progress, the Dock icon shows a bar
(the mean of the running tasks that report one); that needs no permission. The Linux app gets neither for now.

## DEC-023: A one-file task given several files runs once per file (2026-10-21, chosen by Deva)
Deva picked "Run on many files" for 0.2.0. No manifest changes: any task whose main input takes one file can be
given several (dropped, chosen, or opened with Knobs), and Run goes through them one after another in the shared
TaskSession. Each file's command is built just before it runs, so output names are picked knowing what the earlier
files wrote and nothing is overwritten. The command bar shows the first file's command. A file that fails doesn't
stop the others; the result names the ones that didn't work, and the run counts as failed only when every file
failed. Cancel stops the current file and starts no more. History gets one entry and the notification (DEC-022)
fires once per run, not per file. Tasks whose input takes several files at once (Merge PDFs) are unchanged. The
Linux window still takes one file per run; its shared code supports several.

## DEC-024: Updates through Sparkle, asking first (2026-10-21, chosen by Deva)
Deva picked "Sparkle, asks first" for 0.2.0. The Mac app embeds Sparkle 2.10.0 (pinned in `project.yml`; MIT, and
its license ships in the app). Nothing is checked on the first launch; on the second, Sparkle asks whether to check
automatically, and nothing goes over the network before that answer or a press of Check for Updates…. The Knobs menu
has Check for Updates… and a Check for Updates Automatically toggle, so the answer can be changed later. System
profiling stays off, Sparkle's default, so a check is one HTTPS request for the feed whose only detail is the
User-Agent "Knobs/<version> Sparkle/<version>".
- The feed is `https://knobs.pages.dev/appcast.xml`, made by `scripts/release.sh` and listing DMGs on the GitHub
  release, so the website carrying a new feed is deployed only after `gh release create`, like the download
  buttons. Every copy from 0.2.0 on asks that address, so the pages.dev name must keep working, or redirect, after
  the domain arrives.
- Updates are signed with an EdDSA key that only Deva holds, in the login keychain under the account `knobs`
  (`generate_keys --account knobs`). The app carries the public half and checks the signature before it opens the
  DMG (`SUVerifyUpdateBeforeExtraction`). `release.sh` refuses to release without the public key in `project.yml`,
  and fails when the new feed entry isn't signed. Sparkle orders updates by `CFBundleVersion`, which goes up by one
  every release; `release.sh` checks it against the feed.
- Sparkle starts once the main window is up. Started with the app, its question appeared before SwiftUI opened the
  window, SwiftUI then opened none, and answering the question closed the last window and quit Knobs.
- Debug builds have no updater: they share the installed app's bundle id, and so its Sparkle settings.
- 0.1.0 has no updater, so its users hear about 0.2.0 from the website or GitHub only. The Linux app doesn't update
  itself; the AUR package updates through the AUR, and a .deb or .rpm by installing the newer one.
