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
- Not a redesign regression: the build of 6ebca0b, before the redesign, does the same.
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
