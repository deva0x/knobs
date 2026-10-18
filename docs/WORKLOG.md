# Work log

Append-only. Add entries only with `scripts/log.sh`, which stamps the time (Asia/Kolkata), the agent and
the current commit. Never edit, delete or reorder an entry. To fix a mistake, append a correction.

Each entry uses these headings:
- **Work:** what was done (and, for a new task, the four lines: outcome, evidence, boundaries, stop condition)
- **Files and decisions:** what changed, and any decision made
- **Validation:** the commands actually run and their actual results
- **Bugs and blockers:**
- **Next:** the exact next action

## 2026-10-18 08:24 IST · Claude Code (Opus 5.5) · HEAD 9c35b01

**Work:** M0 foundations. Outcome: repo with plan, process docs, local CI and hooks, ready for an unattended build. Evidence: `scripts/ci.sh` passes. Boundaries: no feature code, no remote. Stop: first commit made.
**Files and decisions:** CLAUDE.md (template filled in), AGENTS.md, docs/PLAN, STATUS, WORKFLOW, MANIFEST_FORMAT, DECISIONS (DEC-001 to DEC-010), BUGS, WORKLOG; scripts/ci.sh, log.sh, install-hooks.sh, run-app.sh, hooks/pre-commit and pre-push; skeleton Package.swift, KnobsCore, test, App, project.yml. Name "Knobs", MIT license and bundle id io.github.deva0x.Knobs are working choices pending Deva (DEC-010).
**Validation:** `scripts/ci.sh` full: PASS (lint ok, 1 test passed, Debug app build ok). The no-hosted-CI check was tested by creating .github/workflows: ci.sh failed as intended, then passed after it was removed. The pre-commit hook ran `ci.sh fast` on commit 9c35b01: PASS.
**Bugs and blockers:** The standing authorization in CLAUDE.md is PENDING Deva's yes. There's no Developer ID Application certificate and no `knobs-notary` profile yet (only needed for M7).
**Next:** After Deva approves, start M1: the `ToolManifest` model plus decoding of Manifests/ffmpeg.json.

## 2026-10-18 08:45 IST · Claude Code (Opus 5.5) · HEAD d3475f8

**Work:** M1 and M2. Outcome: KnobsCore loads and validates manifests, builds argv plus a colored preview from the same parts, and runs tools with streamed output, progress, cancel and a bounded log. Evidence: `swift test`. Boundaries: no UI. Stop: tests green and committed.
**Files and decisions:** Sources/KnobsCore/Manifest/* (strict JSON reader with exact error paths, validator), Command/* (CommandBuilder, ArgumentSplitter, ShellQuoting, OutputNamer), Running/* (ToolLocator, ToolRunner, ProgressParser, OutputLog); Manifests/ffmpeg.json (6 tasks); MANIFEST_FORMAT gained symbol, tint, progress, {extra} and the .ext path part. Deployment target is now macOS 26 (DEC-012). Standing authorization was recorded (DEC-013). Installed imagemagick, pandoc, exiftool, ocrmypdf, ghostscript, whisper-cpp, rsync and sevenzip, and downloaded ggml-tiny.en.bin into .cache/models.
**Validation:** `swift test`: 83 tests in 11 suites passed. `swift test --filter FFmpegIntegrationTests` ran for real (0.6 s, every ffmpeg task produced its output file). Fast mode skips the integration suite (81 tests). Pre-commit hook passed on e6fd8d2 and d3475f8.
**Bugs and blockers:** none. The first ocrmypdf install hit a Homebrew lock from the parallel install; the retry succeeded.
**Next:** M4 thin app slice with ffmpeg, then screenshots and a design review.

## 2026-10-18 09:00 IST · Claude Code (Opus 5.5) · HEAD 3920f5e

**Work:** M4 app slice, M6 manifests for all ten tools, and the M8 website (built by a website subagent and reviewed here).
**Files and decisions:** App/ now has AppModel, TaskSession, a sidebar, tool gallery, task workspace, drop zone with Quick Look, a glass command bar with colored preview, result, failure and cancel cards, an output console, a ⌘K palette, and opening files with Knobs (Dock or `open -a`). Manifest format extensions: `equals` conditions, `{output.*}` and `.base` path parts, folder defaults with `~`, and `outputPathPattern`. Nine new manifests. ImageMagick text uses /System/Library/Fonts/Helvetica.ttc because ImageMagick has no default font. 7-Zip progress uses backspaces, so the runner treats 0x08 as a line break. website/ holds a static site; the agent's report lists its fonts (Archivo, IBM Plex Mono) and checks.
**Validation:** `swift test --filter IntegrationTests`: all 11 integration tests across 10 suites pass, running every task of every tool on generated fixtures. yt-dlp runs offline through --enable-file-urls; whisper transcribes `say` output containing "hello". In the app, Shrink a video on a 21.2 MB sample gave a playable 1280x720 H.264 file of 1.6 MB (−92%) in 2 s, checked with ffprobe; screenshot at docs/screenshots/m4-shrink-video-done-dark.jpg. App builds with warnings as errors. Website: the agent ran three review rounds and saved screenshots; desktop light and dark were spot-checked here.
**Bugs and blockers:** Ghostscript treats % in output file names specially, so a file name containing % would produce a wrong output name. Not yet handled (to log in BUGS).
**Next:** M5 (presets, remembered values, recent runs), M7 (All options and Add a tool), then a UI review loop across every tool in light and dark, then full code review rounds.

## 2026-10-18 15:11 IST · Claude Code (Opus 5.5) · HEAD df7998f

**Work:** M5 presets and history, M7 All options and Add a tool, a UI review pass in dark mode, and M9 pieces (icon, About, release script, README, CONTRIBUTING, CHANGELOG). Outcome: every built feature committed and the docs match. Evidence: `scripts/ci.sh` and in-app checks. Boundaries: inside the repo only, no push, no signing setup. Stop: the screen locked during the UI pass, so screen-independent work went next.
**Files and decisions:** Commits e666504 (remembered settings, presets, recent runs), cebec4b (HelpParser and HelpTaskBuilder), 66bbe28 (All options view, Add a tool sheet, palette and navigation fixes), 6a0964e (Open With chooser, large link field for link tasks, number fields, compact report results, folder icons and expanded ~ paths), ed93a85 (app icon drawn by scripts/make-icon.swift, About panel), 78f3135 (scripts/release.sh; BUG-001 logged), 8f49c25 (README, CONTRIBUTING, CHANGELOG 0.1.0), 2c79664 (test fixtures excluded from the test target, which removed an SPM warning). release.sh signs and notarizes only when a Developer ID certificate and the knobs-notary profile exist; otherwise it makes an unsigned DMG and says so.
**Validation:** `scripts/ci.sh` (full): PASS, including every task of every tool running for real. Pre-commit `ci.sh fast` passed on every commit (112 unit tests). In the app: All options for ffmpeg, Add a Tool with jq, ⌘K, the Open With chooser, and yt-dlp's link field with Paste and the folder icon on "Save in". Debug app builds with warnings as errors. The icon was inspected at 1024, 64 and 16 px. Reproduced BUG-001 with gs on the command line. Not checked: the icon in the Dock and the About window (the screen was locked).
**Bugs and blockers:** BUG-001 open (Ghostscript `%` in file names). No Developer ID Application certificate in the keychain (Waiting on Deva in STATUS). Noticed for the code review: ⌘R is bound both in the Task menu and on the command bar's Run button.
**Next:** full code review of KnobsCore and the app, fix what it finds, then continue the UI pass and screenshots when the screen is available.

## 2026-10-18 15:36 IST · Claude Code (Opus 5.5) · HEAD 881a412

**Work:** Full code review, round 1. Outcome: every confirmed finding from four parallel read-only reviewers (core manifest/command, core running/help/library, app model, app views) fixed or consciously deferred. Evidence: failing tests first, then `scripts/ci.sh` full. Boundaries: repo only, no push, no UI verification (screen locked). Stop: CI green and committed.
**Files and decisions:** Commits e139085 (quit stops runs after asking; sizes measured off the main thread; safer Open With matching), afe2bc1 (secret fields banned from output names; {extra} banned inside if; POSIX word splitting; output names trimmed of edge dots; leading = quoted; symlink-safe manifest reads; spec lists every validation rule), da6e454 (VoiceOver-reachable All options controls, Reduce Motion crossfades, shortcuts only in menus plus Open Result ⌘O, no file I/O in body, DESIGN type sizes and separator hairlines, signal orange only on Run, console stops following when scrolled up, Clear Recent Runs), 5b7a5ea (progress read outside the run lock; bounded event buffer; process-group SIGTERM/SIGKILL; NaN progress ignored; help parser fixes for wrapped lines, bracketed values, multi-value options; password options become secret fields; unreadable library set aside instead of overwritten), 8058f9b (test waits for zombie reaping), 10af92b (SECURITY.md), and the BUG-001 fix ({output.percentDoubled}). Earlier this stretch: be605c6 replaced the flat icon set with a layered Icon Composer bundle (App/AppIcon.icon) because the tinted icon style turned the flat icon one muddy color.
**Validation:** `scripts/ci.sh` full: PASS (139 tests in 26 suites, every task of all ten tools running for real, Debug app build with warnings as errors). The first full run failed once on the new process-group test (zombie not yet reaped); fixed and the test passed 5 times in a row, then full CI passed. Help parsing rechecked on all 11 fixtures: ghost options gone, multi-value options only jq --arg/--argjson/--rawfile, magick -limit/-set, yt-dlp --alias. Real gs wrote `out 50%d off.pdf` with the escaped name. Icon rendered from the built app in light and dark appearance.
**Bugs and blockers:** BUG-001 fixed. Not verified on screen (locked): the quit dialog, Open With matching, Reduce Motion, the console follow behavior, and the new icon in the Dock. Deferred low items: output numbering style ("a 2 2.txt"), relative output paths reported by a tool, wall-clock duration, an added tool not reopened on relaunch.
**Next:** round 2 review of the diff c049ba0..HEAD, then the UI pass when the screen is available.
