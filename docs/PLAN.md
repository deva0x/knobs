# Knobs: build plan for v0.1.0

Knobs is an open-source native Mac app that turns command-line tools into beautiful Mac windows.
You pick a tool and a task ("Shrink a video"), drop in a file, set plain controls, and press Run. The exact
command is always shown, and Knobs runs it as an argument list, never through a shell.

"Knobs" is a working name. Deva can rename it before the first public release.

This file is the ordered checklist. Check a box only when its exit check has passed in the same session,
and record the evidence in `docs/WORKLOG.md`. `docs/STATUS.md` says where work currently stands.

## Quality bar

Deva's direction (2026-10-18): a very premium app with a new, modern UI, and a website that stands out.
Keep iterating the UI until a demanding human would call it excellent. The code must be written properly.
`docs/DESIGN.md` holds the design direction and the review checklist that UI work is judged against.

## Scope of v0.1.0

- 10 tools with hand-written manifests: ffmpeg, yt-dlp, ImageMagick, pandoc, exiftool, ocrmypdf,
  Ghostscript, whisper.cpp, rsync, 7-Zip.
- Three layers for every tool (DEC-011):
  1. Tasks: the everyday jobs in plain words. 5 to 6 for ffmpeg, yt-dlp and ImageMagick, 3 to 4 for the others.
  2. An "Extra arguments" box on every task, for options the task doesn't show.
  3. "All options": a generated view of every option from the tool's own help text.
- "Add any tool": the same generated view for tools that have no manifest.
- Presets, recent runs, and a command palette (⌘K) that reaches every task.
- A signed, notarized DMG, a README with screenshots, and a standout website.

Out of scope for v0.1.0: installing tools for the user (Knobs shows the `brew install` command to copy),
chaining tools into recipes, auto-update, the Mac App Store (Knobs can't be sandboxed, see DEC-003),
localization, and Intel Macs (DEC-005).

## Milestones

Every milestone ends with `scripts/ci.sh` passing, plus the milestone's own check listed below.

### M0. Foundations
- [x] Repo, template guardrails, docs, local CI, git hooks, first commit
- Exit: `scripts/ci.sh` passes. `git log` shows the first commit. WORKLOG has an entry.

### M1. Core: manifests and command building (KnobsCore, no UI)
- [x] `ToolManifest` model decoded from JSON, following `docs/MANIFEST_FORMAT.md`
- [x] Validation with clear errors: unknown keys and field references, defaults outside their range, duplicate ids, a missing or repeated `{extra}`
- [x] `CommandBuilder`: manifest task plus field values gives an argv `[String]`; a value is always exactly one argument
- [x] Extra arguments: the box's text is split into words with quote rules, by Knobs itself, never by a shell
- [x] Output path derivation that never overwrites an existing file (adds " 2", " 3", and so on)
- [x] Display rendering of argv with shell-style quoting, used only for the command preview and copying
- [x] ffmpeg manifest written as the reference example
- Exit: unit tests cover decoding, every validation error, argv building (golden tests), word splitting, quoting and output naming.

### M2. Core: running tools
- [x] `ToolLocator`: finds executables in `/opt/homebrew/bin`, `/usr/local/bin` and the system paths, because apps opened from Finder don't get the shell's PATH
- [x] `ToolRunner`: launches `Process` with argv, streams stdout and stderr, supports cancel (SIGTERM, then SIGKILL after a grace period), reports the exit status
- [x] Output buffer capped at the last 5,000 lines
- [x] Integration test: really runs ffmpeg on a generated 1-second clip (`-f lavfi testsrc`); skips with a message if ffmpeg is missing
- Exit: tests pass, and the integration test passes on this Mac.

### M3. Design direction
- [x] `docs/DESIGN.md`: principles, layout, type, color, motion, components, and the review checklist
- [x] Brand basics shared by the app and the website: name treatment, accent color, icon concept
- Exit: DESIGN.md exists and the app and website briefs both point to it.

### M4. App: end-to-end with ffmpeg, premium from the start
- [x] App shell: sidebar of tools, task gallery per tool, task workspace (SwiftUI, macOS 26+, Liquid Glass)
- [x] Field controls for every field kind, styled to DESIGN.md
- [x] Drop zone for files, with a Quick Look thumbnail of what was dropped
- [x] Live command preview, colored by part (tool, flags, values, paths), with Copy
- [x] Extra arguments box (collapsed by default)
- [x] Run and Cancel, live progress and output, done and failed states, result card with Open, Reveal in Finder and drag-out
- [x] "Not installed" state showing the `brew install` command with Copy
- Exit: build and launch the app, shrink a real video with ffmpeg, confirm the output exists and plays. Screenshot saved in `docs/screenshots/`, and the DESIGN.md checklist passes.

### M5. App: presets, history, palette, polish
- [x] Save, apply, rename and delete presets per task (JSON in Application Support). Rename is unit tested; not yet seen on screen
- [x] Remember the last values per task, and a recent-runs list
- [x] Command palette (⌘K) across every tool and task
- [x] Keyboard: ⌘R runs, ⌘. cancels, ⌘K opens the palette
- [x] Empty states and error messages in plain words
- [x] UI review loop: screenshot every screen in light and dark mode, judge it against DESIGN.md, fix, repeat until it passes (WORKLOG 16:39 on 2026-10-18 and the 2026-10-19 entries)
- Exit: preset store tests pass, presets survive a relaunch, and the review loop's final screenshots are in `docs/screenshots/`.

### M6. All ten tools
For each tool: install it with Homebrew, write its manifest, add golden argv tests, add an integration test
that runs one real task on a tiny fixture, and try it once in the app.
- [x] ffmpeg (5 to 6 tasks): shrink, convert, trim, extract audio, make a GIF, remove sound
- [x] yt-dlp (5 to 6): video, audio only, choose quality, subtitles, a whole playlist, thumbnail (integration test uses a local file, no network)
- [x] ImageMagick (5 to 6): resize, convert format, compress, crop or pad to a square, add a watermark text, strip metadata
- [x] pandoc (3 to 4): Markdown to Word, Word to Markdown, Markdown to HTML, to EPUB
- [x] exiftool (3 to 4): show metadata, remove all metadata (copy kept), remove GPS location only, rename photos by date taken
- [x] ocrmypdf (3 to 4): make searchable, deskew and clean, force OCR, choose language
- [x] Ghostscript (3 to 4): compress a PDF, merge PDFs, convert to grayscale, extract pages
- [x] whisper.cpp (3 to 4): transcribe to text, to subtitles (SRT, VTT), translate to English
- [x] rsync (3 to 4): copy a folder, mirror a folder, preview changes (dry run), back up with exclusions
- [x] 7-Zip (3 to 4): create an archive, create with a password, extract, test an archive
- Exit: every manifest validates, golden and integration tests pass, and each tool was run once in the app.

### M7. All options and Add any tool (time-boxed: 4 hours)
- [x] Parser for common `--help` layouts (`-x, --long VALUE  description`)
- [x] "All options" view for every tool: searchable list, a toggle or field per option, built into argv
- [x] "Add any tool": choose any executable and get the same view
- [x] Fixture tests using real `--help` output captured from at least 6 tools
- Exit: tests pass, "All options" works for all 10 tools, and "Add any tool" works for `jq`, `fd` or `curl`.
- If the time box runs out, ship what's solid behind clear "best effort" wording and log the rest in BUGS.

### M8. Website
- [x] Static site in `website/` (no build server needed), following DESIGN.md and studied reference sites
- [x] Hero, live demo of a command turning into controls, tool gallery, how manifests work, download, open-source section
- [x] Real app screenshots, fast, accessible, works at phone width, light and dark
- [x] Reviewed in a browser at desktop and phone sizes, then iterated until it stands out
- Exit: screenshots of the site in `docs/screenshots/website/`, Lighthouse-style checks noted in WORKLOG.

### M9. Ship-ready
- [x] App icon and About window (version, license, link to the repo)
- [ ] Accessibility pass: labels on every control, VoiceOver reads the form in order, keyboard-only use works
- [x] `scripts/release.sh`: archive, sign with Developer ID, notarize, staple, DMG, checksum
- [x] README with screenshots, CONTRIBUTING (how to add a manifest), CHANGELOG
- Exit: `scripts/ci.sh release` passes, a notarized DMG installs and opens on this Mac without a warning, and `spctl -a -vv` accepts the app.
- If the Developer ID certificate or the notary profile is missing, build everything else, leave an unsigned DMG, and list the missing step under "Waiting on Deva" in STATUS.

### M10. Publish (only Deva can do this)
- [x] Name and license settled: Knobs, MIT (DEC-018, on Deva's go-ahead)
- [x] Deva creates the GitHub repo (or approves creating it)
- [x] Deva turns off GitHub Actions for the repo before the first push (Settings → Actions → General → Disable actions), and leaves CodeQL default setup and Dependabot off. An empty `.github/workflows` doesn't stop GitHub's own default workflows.
- [x] Deva pushes
- [x] Deva approves uploading the DMG with `gh release create` (a release upload, not GitHub Actions)
- [x] Website hosting chosen: Cloudflare Pages by direct upload (DEC-018). GitHub Pages builds run on Actions, so a direct upload (for example Cloudflare Pages through `wrangler pages deploy` from this Mac) fits DEC-002 better.

### M11. Linux (DEC-014, DEC-015)
- [x] Spike: KnobsCore builds and its tests pass on Ubuntu, Fedora and RHEL in local containers
- [x] `scripts/ci.sh linux`: KnobsCore and KnobsSession built and the core tests run on Linux, locally
- [x] `KnobsSession` shared by both apps (TaskSession moved out of the Mac app)
- [x] One `Toolbox` in `KnobsSession` for both apps' tools, sessions, runs and saved settings (review finding 9)
- [x] Thin slice in `linux/`: tools, a tool's tasks, every field kind as an Adwaita row, the live command, Run
  with progress, output and Cancel, the result with Open, and settings remembered between launches
- [x] .deb and .rpm packages with the manifests, a desktop entry and an icon (`scripts/linux.sh package`)
- [x] All options and Add a Tool on Linux
- [x] The GTK 4.20 floor accepted, AppImage dropped, Flatpak deferred (DEC-015, DEC-018)
- Exit: the .deb installs and runs Shrink a video in a clean Ubuntu 26.04 container, the .rpm in a clean
  Fedora container, both checked through Broadway.

### M12. PDF tools (2026-10-20, Deva's request)
Same steps as M6 for each tool, plus a card in the website's tool gallery and the Linux package lists. The
website and README describe them from the next release on.
- [x] qpdf (5): rotate pages, pick and reorder pages, protect with a password, remove a password, repair
- [x] img2pdf (1): turn images into a PDF
- [x] pdftoppm, from Poppler (2): a page as an image, and every page as images into a new folder that Knobs
  makes first (`output.newFolder`, DEC-021), since pdftoppm can't make one and would replace same-named files
- [x] pdftotext, from Poppler (1): PDF to text
- Exit: every manifest validates, golden and integration tests pass, and each tool was run once in the app.

### M13. Release 0.2.0 (2026-10-21, everything Deva picked)
One commit or more per item, each with its docs, tested, and tried in the app when it shows on screen.
- [x] BUG-018: no flag ending in a full stop in All options
- [x] Linux file chooser filters img2pdf's image types
- [x] qpdf: Split a PDF, one PDF per page into a new folder
- [x] Result card shows the size change only when input and output are the same kind of file
- [x] One `brew install` line for every missing tool, and a pointer to brew.sh when Homebrew is missing
- [x] A notification and Dock progress when a run finishes while Knobs is in the background (Mac)
- [x] Run a single-file task on many files, one after another
- [ ] Updates through Sparkle, asking before the first check (Mac)
- [ ] Homebrew cask (Deva creates `deva0x/homebrew-knobs`)
- [ ] Release files: version 0.2.0, CHANGELOG, README tools, website `#release`, Linux packages checked in
  clean containers, then Deva runs `scripts/release.sh 0.2.0` and `gh release create`; after that the website,
  the cask and the AUR
- Exit: `scripts/ci.sh` and `scripts/ci.sh linux` pass, every new piece was tried in the app, and the 0.2.0
  files are on GitHub.

## Order and dependencies

M0 → M1 → M2 → M3 → M4 → M5 → M6 → M7 → M9 → M10. M8 (website) can run alongside M4 to M7 because it only
touches `website/`; its screenshots come from the app once M5 is done. Tools in M6 are independent of each
other, so a blocked tool is logged and skipped. M7 never blocks M9. M11 (Linux) touches only `linux/` and
the shared packages, and never blocks the Mac release.
