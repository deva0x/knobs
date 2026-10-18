# Knobs: build plan for v0.1.0

Knobs is an open-source native Mac app that turns command-line tools into ordinary Mac windows.
You pick a tool and a task ("Shrink a video"), drop in a file, set plain controls, and press Run. The exact
command is always shown, and Knobs runs it as an argument list, never through a shell.

"Knobs" is a working name. Deva can rename it before the first public release.

This file is the ordered checklist. Check a box only when its exit check has passed in the same session,
and record the evidence in `docs/WORKLOG.md`. `docs/STATUS.md` says where work currently stands.

## Scope of v0.1.0

- 10 tools with hand-written manifests: ffmpeg, yt-dlp, ImageMagick, pandoc, exiftool, ocrmypdf,
  Ghostscript, whisper.cpp, rsync, 7-Zip.
- Each manifest offers 2 to 4 everyday tasks, not every flag.
- "Add any tool": a best-effort window built from a tool's `--help` text.
- Presets: save a task's current settings under a name.
- A signed, notarized DMG, plus a README with screenshots.

Out of scope for v0.1.0: installing tools for the user (Knobs shows the `brew install` command to copy),
chaining tools into recipes, auto-update, the Mac App Store (Knobs can't be sandboxed, see DEC-003),
localization, and Intel Macs (DEC-005).

## Milestones

Every milestone ends with `scripts/ci.sh` passing, plus the milestone's own check listed below.

### M0. Foundations
- [x] Repo, template guardrails, docs, local CI, git hooks, first commit
- Exit: `scripts/ci.sh` passes. `git log` shows the first commit. WORKLOG has an entry.

### M1. Core: manifests and command building (KnobsCore, no UI)
- [ ] `ToolManifest` model decoded from JSON, following `docs/MANIFEST_FORMAT.md`
- [ ] Validation with clear errors: unknown field references, defaults outside their range, duplicate ids
- [ ] `CommandBuilder`: manifest task plus field values gives an argv `[String]`; a value is always exactly one argument
- [ ] Output path derivation that never overwrites an existing file (adds " 2", " 3", and so on)
- [ ] Display rendering of argv with shell-style quoting, used only for the command preview and copying
- [ ] ffmpeg manifest written as the reference example
- Exit: unit tests cover decoding, every validation error, argv building (golden tests), quoting and output naming.

### M2. Core: running tools
- [ ] `ToolLocator`: finds executables in `/opt/homebrew/bin`, `/usr/local/bin` and the system paths, because apps opened from Finder don't get the shell's PATH
- [ ] `ToolRunner`: launches `Process` with argv, streams stdout and stderr, supports cancel (SIGTERM, then SIGKILL after a grace period), reports the exit status
- [ ] Output buffer capped at the last 5,000 lines
- [ ] Integration test: really runs ffmpeg on a generated 1-second clip (`-f lavfi testsrc`); skips with a message if ffmpeg is missing
- Exit: tests pass, and the integration test passes on this Mac.

### M3. App: thin end-to-end slice with ffmpeg
- [ ] App shell: sidebar of tools, list of tasks, form area (SwiftUI, macOS 15+)
- [ ] Form renderer: one control per field kind (file, folder, choice, integer, number, toggle, text)
- [ ] File drag-and-drop onto the form
- [ ] Live command preview with a Copy button
- [ ] Run and Cancel, a streaming output view, done and failed states, Reveal in Finder for the output
- [ ] "Not installed" state showing the `brew install` command with a Copy button
- Exit: build and launch the app, shrink a real video with ffmpeg, confirm the output exists and plays. Screenshot saved in `docs/screenshots/`.

### M4. Presets and polish of the slice
- [ ] Save, apply, rename and delete presets per task (JSON in Application Support)
- [ ] Remember the last values per task
- [ ] Keyboard: ⌘R runs, ⌘. cancels, ⌘C in the preview copies
- [ ] Empty states and error messages in plain words
- Exit: tests for the preset store, and a manual check of presets surviving a relaunch.

### M5. The other nine tools
For each tool: install it with Homebrew, write its manifest with 2 to 4 tasks, add golden argv tests,
add an integration test that runs one real task on a tiny fixture, and try it once in the app.
- [ ] yt-dlp: download video, download audio only, choose quality (integration test uses `--simulate` against a local file URL, no network)
- [ ] ImageMagick: resize, convert format, compress
- [ ] pandoc: Markdown to Word, Word to Markdown, Markdown to HTML
- [ ] exiftool: show metadata, remove all metadata (copy kept), remove GPS location only
- [ ] ocrmypdf: make a scanned PDF searchable
- [ ] Ghostscript: compress a PDF, merge PDFs
- [ ] whisper.cpp: transcribe to text, transcribe to subtitles (needs a model file; the task asks for it)
- [ ] rsync: copy a folder, mirror a folder (with a dry-run preview first)
- [ ] 7-Zip: create an archive (optional password), extract an archive
- Exit: every manifest validates, golden and integration tests pass, and each tool was run once in the app.

### M6. "Add any tool" from help text (time-boxed: 3 hours)
- [ ] Parser for common `--help` layouts (`-x, --long VALUE  description`)
- [ ] Generated generic task: a toggle or text field per option, plus a free "Other arguments" field
- [ ] Fixture tests using real `--help` output captured from 5 tools
- Exit: tests pass, and "Add a tool" works for at least 3 tools that have no manifest (for example `jq`, `fd`, `curl`).
- If the time box runs out, ship what's solid behind clear "best effort" wording and log the rest in BUGS.

### M7. Ship-ready
- [ ] App icon and About window (version, license, link to the repo)
- [ ] Accessibility pass: labels on every control, VoiceOver reads the form in order, keyboard-only use works
- [ ] Light and dark mode checked
- [ ] `scripts/release.sh`: archive, sign with Developer ID, notarize, staple, DMG, checksum
- [ ] README with screenshots and a GIF, CONTRIBUTING (how to add a manifest), CHANGELOG
- Exit: `scripts/ci.sh release` passes, a notarized DMG installs and opens on this Mac without a warning, and `spctl -a -vv` accepts the app.
- If the Developer ID certificate or the notary profile is missing, build everything else, leave an unsigned DMG, and list the missing step under "Waiting on Deva" in STATUS.

### M8. Publish (only Deva can do this)
- [ ] Deva approves the name and license
- [ ] Deva creates the GitHub repo (or approves creating it) and pushes
- [ ] Deva approves uploading the DMG with `gh release create` (a release upload, not GitHub Actions)

## Order and dependencies

M0 → M1 → M2 → M3 → M4 → M5 → M6 → M7 → M8. M5's tools are independent of each other, so a blocked tool is
logged and skipped. M6 never blocks M7.
