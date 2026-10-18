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
