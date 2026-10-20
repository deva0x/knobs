# Changelog

All notable changes to Knobs are listed here. The format follows Keep a Changelog, and versions follow SemVer.

## [Unreleased]

### Added
- qpdf: rotate pages, pick and reorder pages, split a PDF into one file per page (or per few pages) in a new
  folder, protect a PDF with a password, remove a password, and repair a damaged PDF.
- img2pdf: turn photos and scans into one PDF, a page each, without re-compressing them.
- Poppler's pdftoppm and pdftotext: save a PDF page, or every page, as PNG or JPEG images, and copy a PDF's text
  into a text file. Every page goes into a new folder next to the PDF, so no existing image is replaced.
- Run a task on many files: give a one-file task several files (drop them, choose them, or open them with Knobs)
  and it runs once per file, one after another, with "File 3 of 12" and overall progress. A file that fails
  doesn't stop the others (DEC-023). On Linux the window still takes one file per run.
- Mac: a notification when a run ends while you're in another app (clicking it opens the task), and a progress bar
  on the Dock icon while a task runs. macOS asks for permission the first time (DEC-022).
- Mac: when several tools aren't installed, their panel also shows one `brew install` line for all of them, and
  says when Homebrew itself is missing, with a link to brew.sh.
- Manifests: an output can be a new folder that Knobs makes just before the run (`"newFolder": true`), for tools
  that write several files but can't make a folder.
- Mac: updates. Knobs > Check for Updates… finds, downloads and installs a new version, signed by the Knobs
  project. On its second launch Knobs asks whether to check automatically, once a day; nothing is checked on its own
  before you answer, and Knobs > Check for Updates Automatically changes the answer (DEC-024).

### Fixed
- Linux: the file dialog shows all the types a task takes at once (it opened showing only videos for tasks that
  also take audio), and img2pdf's dialog lists images only.
- All options for qpdf lists each option as qpdf accepts it (`--linearize`, not `--linearize:`), and img2pdf's
  page size, image size and border options are read from their own lines, not from the prose above them. A flag
  that ends a sentence, such as qpdf's `--json-output.`, is no longer listed.

### Changed
- The result card shows the size change only when the output is the same kind of file as the input, such as a
  video shrunk into a video; a PDF turned into text or images, or a folder of results, now just says Done.
- The Arch Linux package is now `knobs-gui-bin`, because the AUR's `knobs` is a different program. It downloads
  its tarball from the GitHub release, and `scripts/linux.sh package` also writes its AUR PKGBUILD and .SRCINFO.

## [0.1.0] - 2026-10-20

The first release.

### Added
- Ten tools, each with everyday tasks in plain words: ffmpeg, yt-dlp, ImageMagick, pandoc, ExifTool,
  OCRmyPDF, Ghostscript, whisper.cpp, rsync and 7-Zip. Every task is checked by a test that really runs it.
- A task window for every task: drop a file, set plain controls, press Run. Live progress, Cancel, and a
  result card with Open, Show in Finder and drag-out.
- The exact command is always shown, colored by part, and can be copied. Tools run as an argument list,
  never through a shell, and Knobs never overwrites an existing file.
- Extra arguments on every task, for options the task doesn't show.
- All options: every option a tool lists in its help, searchable, with a switch or a field for each.
- Add a Tool: any command-line tool on the Mac gets an All options window from its own help.
- Settings are remembered per task, presets can be saved and applied, and recent runs are listed.
- Go to Task (⌘K) reaches every task of every tool. ⌘R runs, ⌘. cancels.
- Opening a file with Knobs from Finder offers the tasks that fit it.
- A "Not installed" screen with the `brew install` command to copy.
- Manifests: a documented JSON format, so adding a tool or a task needs no Swift.
- Local-only CI (`scripts/ci.sh`) and a local release script (`scripts/release.sh`).
- Knobs for Linux, in GTK 4 and libadwaita, sharing the manifests and the core with the Mac app: every task,
  All options with a settings search, and Add a Tool. Packages for Ubuntu 26.04+ (.deb), Fedora 43+ (.rpm) and
  Arch Linux (`knobs-bin`), for arm64 and x86_64, built locally with `scripts/linux.sh package`.
- A tool installed under another name is found under it, and the command shows that name (7-Zip as `7z`).
- Drop files on a tool's page to see the tasks that take them.
- On Linux, closing the window while a task runs asks first, and stops the task before closing.
