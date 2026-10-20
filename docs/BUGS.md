# Bugs

Every bug gets an entry: how to reproduce it, what was expected, what happened, and its status. Keep
resolved entries and record the verified fix with the commit and the check that proved it.

Template:

```
## BUG-NNN: short title (open | fixed | wontfix)
- Found: date, by whom
- Steps: numbered steps that reproduce it
- Expected:
- Actual:
- Fix: commit, and the test or check that proves it
```

## BUG-001: Ghostscript misnames output when the file name contains `%` (fixed)
- Found: 2026-10-18, Claude (Opus 5.5) while testing Ghostscript tasks
- Steps:
  1. Name a PDF `a 50%d.pdf`.
  2. Run Ghostscript → Compress a PDF on it.
- Expected: the output is `a 50%d compressed.pdf`.
- Actual: Ghostscript reads `%d` in `-sOutputFile` as a page-number pattern, so it writes `a 501 compressed.pdf`
  (reproduced on the command line with `gs -sDEVICE=pdfwrite -o "out 50%d off.pdf" ...`, which wrote
  `out 501 off.pdf`). Knobs then can't find the output it expected. `%%` is Ghostscript's escape for a literal `%`.
- Fix: a new path part, `{output.percentDoubled}`, doubles every `%` (Ghostscript's escape for a literal `%`);
  the Ghostscript manifest uses it in `-sOutputFile=`. Tool behavior stays in the manifest. Proven by
  `CommandBuilderTests.ghostscriptGetsPercentSignsDoubledInItsOutputPath`, which failed before the change, and by
  running `gs -sDEVICE=pdfwrite -o "out 50%%d off.pdf"`, which wrote `out 50%d off.pdf`.

## BUG-002: File previews vanished after the round-1 review (fixed)
- Found: 2026-10-18, Claude (Opus 5.5), first on-screen pass after the code reviews
- Steps:
  1. Open a video with Knobs, or drop one on Shrink a video.
  2. Look at the chooser header and the file row.
- Expected: the video's Quick Look preview, or its Finder icon while that loads.
- Actual: no image at all. Round 1 moved the icon lookup into `FileThumbnail`'s `.task`; with no thumbnail and
  no icon yet, its `Group` had no content, so the view, and with it the task that loads both, never appeared.
- Fix: the thumbnail is a `ZStack` with an always-present placeholder, so the task runs. Checked on screen: the
  chooser shows the video's first frame.

## BUG-003: Opening a video offered ExifTool's photo tasks first (fixed)
- Found: 2026-10-18, Claude (Opus 5.5), on-screen pass
- Steps: open a .mov with Knobs from Finder.
- Expected: the video tasks (ffmpeg) first.
- Actual: choices followed tool order, so "Show hidden details" and "Rename photos by date taken" led.
- Fix: choices are ranked by fit, from the manifests alone: tasks that accept fewer types come first (ffmpeg's
  `public.movie` before ExifTool's image, video and PDF), then manifest order. Checked on screen.

## BUG-004: Every file opened with Knobs opened another window (fixed)
- Found: 2026-10-18, Claude (Opus 5.5), on-screen pass
- Steps: open two files with Knobs from Finder (or `open -a Knobs file`) while it runs.
- Expected: the one Knobs window takes the files.
- Actual: a `WindowGroup` scene answers each open event with a new window, so three identical windows appeared.
- Fix: the app uses a single `Window` scene. Checked on screen: two opens, one window.

## BUG-005: The output console opened mid-run showed the first lines, not the newest (fixed)
- Found: 2026-10-18, Claude (Opus 5.5), on-screen pass (also suspected by the round-2 review)
- Steps: start Shrink a video on a long clip, then press Show output.
- Expected: the newest lines, following as more arrive.
- Actual: the top of the log, which then never followed, because the console counted itself as scrolled up.
- Fix: the console starts anchored at the bottom (`defaultScrollAnchor(.bottom, for: .initialOffset)`).

## BUG-006: A failed run crashed the app on the redesigned failure screen (fixed before commit)
- Found: 2026-10-18, Claude (Opus 5.5), on-screen pass of the uncommitted redesign
- Steps: open a video in Shrink a video, put `-not_a_real_option 1` in Extra arguments, press Run.
- Expected: the failure screen with ffmpeg's error line.
- Actual: the app quit. AppKit raised "The window has been marked as needing another Update Constraints in
  Window pass…" (and, without text selection, the same loop as a layout pass), from the split view updating its
  column's minimum size again and again.
- Cause: the error text had `.fixedSize(horizontal: false, vertical: true)`, so the stage's minimum height
  depended on its width, which the split view and inspector kept renegotiating. Removing only text selection
  still crashed; removing only `fixedSize` stopped it.
- Fix: the error text wraps normally inside the 560 pt column. Checked on screen: the same run now shows
  "ffmpeg stopped with an error" with Change Settings and Show Output, and the app stays up.

## BUG-007: Add a Tool drew on top of the Recent list (fixed)
- Found: 2026-10-18, Claude (Opus 5.5), full-resolution window capture
- Steps: have five or more recent runs, so the sidebar list reaches the bottom of the window.
- Expected: Add a Tool readable at the bottom of the sidebar.
- Actual: the button was a bottom safe-area inset with nothing behind it, so recent rows scrolled under its
  label and both were drawn on top of each other. Glass behind it was tried and was still too clear.
- Fix: Add a Tool sits below the list in a stack, so no row passes beneath it. Checked in a capture.

## BUG-008: The command bar showed two overlapping copies of the command (fixed)
- Found: 2026-10-18, Claude (Opus 5.5), window captures while opening a task
- Steps: open a file into Shrink a video while the Knobs window is behind other windows, then capture it.
- Expected: one line, "ffmpeg -hide_banner -nostdin…".
- Actual: two truncations of the command cross-faded on top of each other. A window that isn't drawn on
  screen doesn't finish animations, so the half-faded frame stayed; on screen it flickers briefly.
- Fix: the command text never animates; it follows each change at once. Checked in a capture.

## BUG-009: Opening a task in another tool showed that tool's home instead of the task (fixed)
- Found: 2026-10-18, Claude (Opus 5.5), on-screen pass with a fresh data folder
- Steps: open a task in one tool (Compress an image, ImageMagick). Then either open a video with Knobs and
  choose Shrink a video, or click a Recent row that belongs to a different tool.
- Expected: the chosen task, with the file in it.
- Actual: the other tool's home. The task's session does get the file; clicking its card shows it ready.
- Evidence (temporary logging of every write): `open(toolID:taskID:)` sets the tool and its path together.
  The detail's `NavigationStack` is recreated per tool by `.id(tool.id)`; the outgoing stack then writes an
  empty path through the shared binding, and the new stack also ignores a path it starts with.
- Tried, none reliable: (1) a path per tool with the stack bound to its own tool's entry: the outgoing stack
  then clears only its own entry, but the new stack still shows the home; (2) writing the path again in the
  new stack's `onAppear` (inside the id): worked once for the chooser, then failed for Recent and on a rerun
  of the chooser, so it was timing; (3) one persistent stack without the stack-level id: still the home.
- Not a redesign regression: the build of 5f1a1c8, before the redesign, does the same.
- Status before the fix: reverted to the committed code. Within the same tool everything worked.
- Fix (2026-10-19, the recorded next idea): switching tools no longer sets the path in the same moment. The
  model keeps a pending task for the new tool, and that tool's home opens it from its `.task` once it is on
  screen; choosing a tool in the sidebar drops any pending task. Reproduced first on the current build (Recent
  "Shrink a video" from ImageMagick showed ffmpeg's home), then checked with the fix: six Recent switches
  between ImageMagick and ffmpeg with animations off and four with them on all opened the task, and the Open
  With chooser opened Shrink a video and Convert a video with the file in place, twice.

## BUG-010: On Linux, Cancel let a tool run until the SIGKILL three seconds later (fixed)
- Found: 2026-10-18, the Linux spike agent, running KnobsCore's tests in `swift:6.2-noble` on this Mac
- Steps: on Linux, start a long tool from a Swift concurrency or Dispatch thread, then cancel it.
- Expected: the tool gets SIGTERM and stops at once, as on macOS.
- Actual: it ran until the SIGKILL after the grace period. swift-corelibs `Process` spawns the child with the
  calling thread's signal mask, and those threads block SIGTERM (`SigBlk: fffffffe3bfbea27` in
  `/proc/<pid>/status`). The test still passed because its limit, 5 s, was above the grace period.
- Fix: on Linux the runner spawns with an empty signal mask. The test now requires stopping within the grace
  period; without the fix it fails on Linux (3.2 s against 3.0 s), with it `scripts/ci.sh linux` passes.

## BUG-011: On Linux, a task row clicked once before could not open again (fixed)
- Found: 2026-10-18, Claude, checking All options on Linux through Broadway (`scripts/linux.sh run`)
- Steps: open ffmpeg's All options, select 7-Zip in the sidebar, click 7-Zip's All options row.
- Expected: 7-Zip's All options page ("7-Zip isn't installed" in the container).
- Actual: the row lit up and nothing opened. With a freshly started app, the same click worked. The tool page
  opened tasks through list selection. The toolkit reuses the page's list for the next tool and never clears a
  selection whose value no longer matches a row, so the row clicked earlier stayed selected, and clicking a
  selected row reports no change. Giving each page its own identity (`ViewStack(id:)`) rebuilt the list but left
  a blank page when returning to one, with `gtk_root_get_focus` criticals; that attempt was reverted.
- Fix: task rows are activatable `ActionRow`s that open on activation (click or Enter), not on selection. The
  sequence above, Back and reopening the same row, and opening a task in a second tool all work through
  Broadway. The same change turns off Pango markup on every row that shows manifest, help or path text, so a
  file name with `&` or help with `<` shows as written.

## BUG-012: On Fedora, Shrink a video failed with Fedora's own ffmpeg (fixed)
- Found: 2026-10-18, Claude, install-testing the .rpm in a clean `fedora:44` container through Broadway
- Steps: install the .rpm and `ffmpeg-free` (what the .rpm recommends), run ffmpeg → Shrink a video.
- Expected: a smaller H.264 copy, as on macOS and Ubuntu.
- Actual: "ffmpeg stopped with an error: Error opening output files: Encoder not found". Fedora's
  `ffmpeg-free` leaves out libx264, which the task names; it has libopenh264 instead. Tasks that don't re-encode
  work (Remove the sound made a silent copy in 2 s). RPM Fusion's `ffmpeg` has libx264.
- Fix: the task asks for the codec, `-c:v h264`, instead of the encoder, so ffmpeg uses the best H.264 encoder
  it has: libx264 on macOS, Ubuntu and RPM Fusion (checked: "Matched encoder 'libx264'"), libopenh264 with
  Fedora's ffmpeg-free. The x264-only `-preset` and `-crf` are then ignored with a warning, so Quality has no
  effect there. Checked in the installed Fedora app: Shrink a video "Done in 3 s", 5.0 MB to 2.6 MB, 1280x720
  H.264 by libopenh264. The manifest golden test and the ffmpeg integration test pass on macOS.

## BUG-013: On Linux, a file chosen in the file dialog could arrive as a garbled or wrong path (fixed)
- Found: 2026-10-19, Claude, choosing a video in the Broadway container while taking the website's Linux
  screenshots.
- Steps: ffmpeg → Shrink a video → Choose…, type `/home/alex/Videos/Sunset over Goa.mov`, press Enter.
- Expected: the Video row and the command show that path.
- Actual: the row showed `/` followed by unreadable bytes, and the command used them as the input file.
- Cause: Adwaita for Swift's file importer. Its C callback (`gtui_filedialog_open_finish` and the folder one in
  `Sources/CAdw/adwshim.c`) takes the path with `g_file_peek_path`, which borrows it from the GFile, then
  releases the GFile and only afterwards hands the path to Swift. The path is read from freed memory: usually
  still intact, which is why earlier checks passed, sometimes garbage, and it could be another file's path. The
  latest upstream commit (`af5598f`, the one Knobs pins) still has it.
- Fix: Knobs opens GTK's file dialog itself (`linux/Sources/Knobs/FileChooser.swift`) and copies the path with
  `g_file_get_path` before releasing anything; the library's importer is no longer used. Dismissing the dialog
  stays silent, and any other dialog error goes to standard error. Checked through Broadway: the same file
  chosen five times in a row came back as the exact path each time, Escape changed nothing and logged nothing,
  and Shrink a video then ran ("Done in 11 s") and wrote `Sunset over Goa small.mp4` beside the input. The
  packages in `dist/linux/` were rebuilt afterwards.
- Upstream: worth reporting to Adwaita for Swift (Codeberg) once the repository is public; not reported yet.

## BUG-014: On Linux, a tool's output stops after the first 8 KB and the run ends without the rest (fixed)
- Found: 2026-10-19, Claude, running `scripts/ci.sh linux` after the review fixes.
- Steps: `scripts/ci.sh linux`; the test `aBurstOfManyLinesArrivesWholeAndInOrder` runs `/usr/bin/seq 1 5000`.
- Expected: all 5000 lines, in order, then `.finished(.succeeded)`.
- Actual: lines 1 to 1859 only, every time, and the test takes about 2.07 s, which is `ToolRunner.drainTimeout`.
  Lines 1 to 1859 plus the unfinished `1860` are exactly 8192 bytes, so the output handler ran for one read and
  never again; the run then finished through the drain timeout as a success with a truncated log. On a real
  run this would cut the output log and any progress that comes after the first 8 KB.
- Not a regression: the same test against the pre-review `ToolRunner.swift` (commit 7269d78) fails the same way
  on Linux, 3 runs out of 3. The Mac passes it.
- Cause (confirmed 2026-10-19 on swift:6.2-noble, with the byte count of each handler call logged):
  swift-corelibs-foundation's `FileHandle.readabilityHandler` ran once for standard output, read 8192 bytes,
  and was never called again, not even for the end of output; standard error got its one empty read at the end.
  After a short read the handler does run again (5 bytes, then the empty end-of-output read, in a smaller run),
  so it is a full 8192-byte read that leaves it silent.
- Fix: `ToolRun.listen` no longer uses `readabilityHandler`. Each pipe is read with blocking `read` calls on a
  thread of its own, from a duplicate of the pipe's descriptor that the thread closes itself; the threads start
  only once the tool has started. One implementation for both platforms. The drain timeout is unchanged (but see
  BUG-016 for Linux). Checks: the burst test passes on Linux (5 of 5 runs of ToolRunnerTests, then
  `scripts/ci.sh linux`: PASS, 151 tests); `scripts/ci.sh fast` and `scripts/ci.sh` full pass on the Mac. A new
  test, `aHelperThatKeepsTheOutputOpenDoesNotHoldUpTheEnd`, pins the drain timeout; it passed on the Mac before
  and after the change.
- Upstream: reported as swiftlang/swift-corelibs-foundation#5618
  (https://github.com/swiftlang/swift-corelibs-foundation/issues/5618), 2026-10-19, with a standalone program
  (no Knobs code) that loses 15,701 of 23,893 bytes on Swift 6.2.4 and 6.4.1 (5 of 5 runs each) and none on macOS.

## BUG-015: On Linux, the app sometimes crashes in libdispatch after a run is stopped (open)
- Found: 2026-10-19, Claude, checking the new close confirmation through Broadway.
- Steps: ffmpeg → Shrink a video on a 30-second 720p clip → Run → close the window → Stop and Close. Once it
  also happened after plain Cancel presses, in a loop whose timing went irregular.
- Expected: the run stops and the app exits normally (or keeps running after Cancel).
- Actual: twice, the app died with "Bad pointer dereference" on the DispatchWorker thread in
  `_dispatch_event_loop_drain`, while the main thread was still in GTK's loop. One of those was the Stop and
  Close check cited in commit 989f83f, which says "the app exited": it did, after ffmpeg had stopped, but by
  this crash. A plain close with nothing running exits with status 0.
- Seen and not seen: 2 of 4 Stop and Close trials and 1 Cancel loop on HEAD crashed. Afterwards, 12 Cancel
  presses each on 7269d78, d1c75cd and 4340d06, and 6 each on 989f83f built in a worktree and on HEAD, did not
  crash. Not shown to be a regression.
- Cause (hypothesis): the same part as BUG-014. A run's pipes close when `ToolRun` lets its `Process` go, which
  may happen before libdispatch has removed the pipe's read source; a reused file descriptor would then hand
  the event loop a stale source. Fixing BUG-014 by not using `readabilityHandler` would remove that path too.
- After BUG-014's fix (560bad8, 2026-10-19): Knobs no longer creates any dispatch source for a run's pipes. The
  Linux app built from that commit, started as `scripts/linux.sh run` does but with
  `SWIFT_BACKTRACE=enable=yes,interactive=no,output-to=stderr`, ran ffmpeg Shrink a video on a generated 30-second
  720p clip: 23 Run → Cancel cycles with ffmpeg running (cancelled 0.3 to 4 s after Run; counted by the
  partly written output files and a watcher of ffmpeg's process ids), all in one app process that stayed up, with
  no ffmpeg left over; then 5 Stop and Close trials in fresh containers (closed 0.3 to 4 s after Run), each
  exiting with status 0 and no backtrace. No crash.
- Still open: the crash was already rare before the fix (none in 54 Cancel presses on older builds), so its
  absence now does not prove the cause. Close it once it stays absent; if it comes back, the hypothesis above is
  wrong, since the pipe sources are gone.
- Upstream: the same crash (`_dispatch_event_loop_drain`, bad pointer dereference, with `readabilityHandler` on
  pipes) is swiftlang/swift-corelibs-foundation#3276 (https://github.com/swiftlang/swift-corelibs-foundation/issues/3276),
  open since 2020 and reproduced there on Swift 6.4 in September 2026. That supports the hypothesis above.

## BUG-016: On Linux, a run whose tool leaves a helper running looks unfinished until the helper exits (open)
- Found: 2026-10-19, Claude, adding a test for the drain timeout while fixing BUG-014.
- Steps: on Linux, run `/bin/sh -c '/bin/sleep 5 & echo done'` through `ToolRunner` (the test
  `aHelperThatKeepsTheOutputOpenDoesNotHoldUpTheEnd`).
- Expected: `done`, then `.finished(.succeeded)` about 2 s later (`ToolRunner.drainTimeout`), as on the Mac.
- Actual: `.finished` comes after 5 s, when `sleep` exits. `Process.terminationHandler` itself is only called
  then (logged: about 5.5 s after the start), so the drain timeout never gets its chance. The same happens with
  the pre-fix `ToolRunner` (readabilityHandler), so it is older than BUG-014's fix.
- Cause: swift-corelibs-foundation's `Process` (release/6.2, `Sources/Foundation/Process.swift`) learns that the
  tool exited by watching one end of a `socketpair`; the other end is left open in the tool, without
  close-on-exec (its own descriptor-closing loop skips it), so every helper the tool starts inherits it, and the
  socket only reports the hang-up, and `waitpid` only runs, once the last helper has exited.
- Effect: a tool that exits but leaves a helper behind shows as running until that helper exits. Cancel still
  ends it, because Cancel signals the tool's whole process group. No manifest tool is known to do this.
- Upstream: already reported as swiftlang/swift-corelibs-foundation#4795
  (https://github.com/swiftlang/swift-corelibs-foundation/issues/4795), open since 2023, which suggests
  `pidfd_open` or `signalfd` instead of the socket. Not reported again (it would be a duplicate). Open pull
  request #5366 changes the same socket but keeps the child's end inheritable, so it would not fix this.
- Not fixed: Knobs can't reach that descriptor without replacing `Process` on Linux. The test records the
  Linux failure as a known issue (`withKnownIssue`), so it fails, and asks for the marker to be removed, once
  this is fixed.

## BUG-017: qpdf's All options lists flags with a colon that qpdf rejects (open)
- Found: 2026-10-20, Claude, reading the parse of qpdf's help while adding qpdf.
- Steps: parse `Tests/KnobsCoreTests/Fixtures/help/qpdf.txt` (`qpdf --help=all`, qpdf 12) with
  `HelpParser.options(in:)`, or open qpdf's All options in the app and turn on `--linearize:`.
- Expected: one entry per qpdf option, spelled as qpdf accepts it (`--linearize`, `--rotate` with its value).
- Actual: 223 entries, 130 of them spelled with a trailing colon (`--linearize:`, `--rotate:` with the value name
  "rotate"). Run as `qpdf --linearize: in.pdf out.pdf`, qpdf answers "unrecognized argument --linearize:" and
  exits 2.
- Cause: each help topic ends with a "Related options:" list of `  --flag: summary` lines. The parser takes
  `--flag:` as the flag and the summary's first word as the value name. The detailed `== --flag (...) ==`
  sections further down add the right spelling (`--rotate` with `+|-]angle[:page-range`), so most options are
  listed twice, once with the colon.
- Same kind, img2pdf (`Fixtures/help/img2pdf.txt`, img2pdf 0.6.3): a prose line that starts with a flag,
  "  --pagesize options, respectively.", becomes the `--pagesize` entry with the value name "options
  respectively.", and the real `-S, --pagesize LxL` line later is dropped as a duplicate. The prose line
  "  --imgsize options are passed, then the --border option will be ignored." likewise becomes one entry for
  both flags, and the real `-s, --imgsize` and `-b, --border` lines are dropped. The golden count pins 37.
- Effect: qpdf's All options view has many entries that make a command qpdf refuses. qpdf's five tasks are not
  affected; they don't use the help.
- Not fixed yet: the parser should read `--flag: summary` as a flag and its summary, and then keep the entry
  that names a value when a flag is listed twice. That changes how duplicates are handled for every tool, so it
  gets its own change, checked against all the help fixtures. The golden count pins today's parse (223) until
  then.
