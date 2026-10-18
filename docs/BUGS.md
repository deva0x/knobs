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
