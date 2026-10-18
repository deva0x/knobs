# Design

Knobs should feel like a precision instrument: calm, tactile, exact. It isn't a developer tool with a GUI
bolted on. It's a beautiful Mac app that happens to drive powerful tools. Every screen is judged against
the checklist at the end of this file.

## Principles

1. **Tasks, not flags.** People come to "shrink a video", not to set `-crf`. Lead with the job, in plain
   words. The command is shown, but it's never the first thing you have to read.
2. **One clear next step.** Every screen has exactly one primary action. On a task, that's Run.
3. **Show the machine, gently.** The live command preview builds trust and teaches. It's colored, quiet and
   always correct, because it's rendered from the same argv that runs.
4. **Native first.** Use real macOS controls, the system font, SF Symbols, Liquid Glass and standard
   keyboard behavior. Custom styling refines native controls instead of replacing them.
5. **Every state is designed.** Empty, missing tool, ready, running, done, failed and cancelled each have a
   deliberate look and plain words. Nothing is ever just a raw error string.
6. **Quiet motion.** Motion explains a change of state (a drop lands, a run starts or finishes). Springs,
   200 to 350 ms, nothing that loops except a running indicator.

## Brand

- **Name treatment:** "Knobs", set in SF Pro Rounded semibold in the app and in the website's display face
  on the web.
- **Concept:** studio hardware. The products of Braun and Teenage Engineering and the dials on a mixing
  desk: warm neutrals, one vivid signal color, precise small type, generous space.
- **Signal color:** `#FF5B1F` ("signal orange"). The brand mark: the app icon, the website, About, and
  app-level moments such as Go to Task. Inside a tool, the tool's own tint is the accent, including its Run
  button, so a screen never carries two competing accents (decided in the 2026-10-18 redesign: orange Run
  next to a magenta ffmpeg tint read as two primary colors).
- **Neutrals:** the system's own grays in the app. On the web, warm paper `#F4F1EA` and graphite `#141414`.
- **Icon concept:** a single machined dial seen from the front, with an orange indicator mark at about
  two o'clock and fine tick marks around it, on a warm graphite rounded-square base. It must still read at
  16 px. It is an Icon Composer bundle, `App/AppIcon.icon`: three layers (tick marks, knob, glass indicator)
  over a graphite fill, so macOS 26 adds the glass and tints each layer properly in tinted and clear modes.
  `scripts/make-icon.swift App/AppIcon.icon` draws the layers and writes `icon.json`; edit the script and rerun
  it rather than editing the PNGs. `docs/assets/app-icon.png` is the system's rendering, for the README.
- **Tool tints:** each tool has its own tint for its glyph tile, so the sidebar can be scanned by color as
  well as by name. Tints come from the system palette, so they adapt to dark mode:

| Tool | SF Symbol | Tint |
|---|---|---|
| ffmpeg | `film.stack` | purple |
| yt-dlp | `arrow.down.circle` | red |
| ImageMagick | `photo.stack` | teal |
| pandoc | `doc.richtext` | indigo |
| exiftool | `camera.metering.matrix` | orange |
| ocrmypdf | `doc.text.viewfinder` | blue |
| Ghostscript | `doc.on.doc` | gray |
| whisper.cpp | `waveform` | green |
| rsync | `arrow.triangle.2.circlepath` | cyan |
| 7-Zip | `archivebox` | brown |

## App layout (redesign, 2026-10-18)

The window is one `Window` scene: sidebar, a content area, and on a task an inspector on the trailing edge.

```
┌──────────────┬───────────────────────────────────────┬──────────────────┐
│ ⌕ Find a task│  Shrink a video · ffmpeg      [Presets]│  Inspector       │
│              │                                       │  Settings        │
│ Tools        │        ┌──────────────────────┐       │   Size   [720p ▾]│
│  ▣ ffmpeg    │        │                      │       │   Quality ──●── 26│
│  ▣ yt-dlp    │        │   large preview      │       │   Remove sound ◯ │
│  ▣ ...       │        │   (Quick Look)       │       │  Output          │
│              │        └──────────────────────┘       │   Holiday small… │
│ Recent       │      Holiday in Goa.mov               │   next to input  │
│  ...         │   3:00 · 1920×1080 · 350 MB · Movie   │  Extra arguments │
│ + Add a tool │ ╭─ Command bar (glass) ────── [Run] ╮ │   [            ] │
└──────────────┴───────────────────────────────────────┴──────────────────┘
```

- **Sidebar:** the system's glass sidebar. Rows show a 24 pt glyph tile in the tool's tint, then the name. A
  missing tool shows a "Not installed" caption and stays selectable.
- **Tool home:** a hero header washed with the tool's tint (a soft mesh gradient that fades into the window),
  a large glyph tile, the tool's name and summary, and a status line: where it's installed, or the install
  command. Below it, the task cards, larger than before, each naming what it takes ("Video", "PDF") in words
  from the system's own type names. Cards lift slightly and take a tint border on hover (no lift under
  Reduce Motion). Dropping files anywhere on the tool home outlines the page in the tint and opens them in
  that tool's task that takes them, offering a choice when several do; files no task takes are refused and
  the section header says so for a moment.
- **Task stage:** the content area is a stage for the task's main input, not a form.
  - Empty: one large drop target with the kind of file it wants ("Drop a video") and Choose.
  - Filled: a large Quick Look preview with the file's facts underneath as quiet chips, read by file type,
    never by tool: duration and dimensions for video, dimensions for images, page count for PDFs, size and
    kind for everything. Several files show as an overlapping stack with a count.
  - A task whose main input is text, such as a link, shows that field large in the stage.
  - Running: a dial gauge over the preview, a 270° arc of tick marks like the app icon that fills with the
    tool's tint as progress comes in, the percentage and elapsed time at its center. It sits on dark glass so
    it reads over any picture. Without progress, the ticks sweep gently (still under Reduce Motion).
  - Done: before and after. The output's preview takes the stage with the size change as the hero number
    ("−92%", spoken as "92% smaller"), the input to output sizes and time beneath, and Open, Show in Finder
    and drag-out. Only Open is tinted; the other buttons are neutral glass. Report-only tasks show the output
    text instead.
  - Failed or cancelled: a calm panel in the stage with the last useful error line and Show Output.
- **Inspector:** the native trailing inspector (`.inspector`), toggled from the toolbar. Sections: Settings
  (each field as label, help and a full-width control), Output (where the file will go and its name), and
  Extra arguments. On narrow windows it can be hidden; the stage stays usable.
- **Command bar:** a Liquid Glass capsule floating at the bottom of the stage. The syntax-colored command in
  SF Mono, truncated in the middle with the full text in a popover, Copy, then Run in the tool's tint. While
  running: elapsed time, percentage, Show Output and Cancel.
- **Output:** a console panel that slides up over the stage, monospaced and selectable, following new lines
  unless the user scrolls up.
- **All options:** a searchable list of the tool's options in the content area, with the same command bar.
- **Command palette (⌘K):** a centered glass panel with search and results from every tool and task.
- **Not installed:** the tool home and the stage show the `brew install` command in a copyable well with
  Check Again.

## Type

The app uses the system font only. Size roles:
- Tool name on the tool home: 30 pt bold; task title in the window title
- Result hero number: 44 pt bold rounded
- Stage file name: 17 pt semibold
- Section header: 13 pt semibold, secondary color
- Body and labels: 13 pt regular
- Captions and help: 11 pt regular, secondary color
- Command: SF Mono 12 pt

## Color in the command preview

| Part | Color |
|---|---|
| Executable | primary, semibold |
| Flags (`-crf`, `--format`) | the tool's tint |
| Values | primary |
| Paths | secondary, with a small file symbol is optional |
| Extra arguments | primary, with a dotted underline |

## Spacing and shape

- 4 pt base grid. The usual gaps are 8, 12, 16, 24 and 32.
- Corner radii: cards 14 pt, wells and drop zone 12 pt, glyph tiles 6 pt (22 pt tiles) and 10 pt (44 pt tiles).
- Dividers are hairlines in the system separator color. Groups use the grouped-form background, not boxes
  inside boxes.

## Motion

- A drop: the zone's border brightens on hover, and the thumbnail springs in when the file lands.
- Run: the stage dims and the dial gauge fades in over the preview; the command bar turns into progress.
- Done: the output preview crossfades in with a small spring, and the size change counts to its value.
- Respect Reduce Motion: use crossfades instead of movement.

## Website

The same brand, translated to the web: warm paper background, graphite text, signal orange used sparingly,
a distinctive display face for headlines with a clean grotesk for body text and a mono for commands. The
signature moment is an interactive demo: turn a real dial or move a slider, and a command line rewrites
itself live, showing the core idea in five seconds. Study premium Mac app sites (Raycast, Linear,
CleanShot, Things, Arc) for craft and restraint. Don't copy any of them.

## Review checklist

Judge each screen in light and dark mode at the minimum window size (900 × 620) and at a large size:

- [ ] One obvious primary action, in the tool's tint; no second accent competes with it
- [ ] Alignment holds on the 4 pt grid; labels and controls share consistent columns
- [ ] Nothing truncates awkwardly, overlaps, or jumps when the state changes
- [ ] All states for this screen exist and read in plain words
- [ ] The command preview matches what actually runs (it's rendered from the same argv)
- [ ] Every control has an accessibility label; tab order follows reading order; the keyboard shortcuts work
- [ ] Contrast is comfortable in both modes, and nothing relies on color alone
- [ ] Motion is subtle, and Reduce Motion is respected
- [ ] It looks at home next to Apple's own apps on macOS 26, and better than most third-party ones
