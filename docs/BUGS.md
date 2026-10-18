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
