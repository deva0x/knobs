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
- **Signal color:** `#FF5B1F` ("signal orange"). It's used only for the primary action, the focus of
  attention, and the brand mark. In the app it's the app's accent color.
- **Neutrals:** the system's own grays in the app. On the web, warm paper `#F4F1EA` and graphite `#141414`.
- **Icon concept:** a single machined dial seen from the front, with an orange indicator mark at about
  two o'clock and fine tick marks around it, on a warm graphite rounded-square base. It must still read at
  16 px.
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

## App layout

```
┌──────────────┬──────────────────────────────────────────────────────┐
│ (glass       │  Toolbar: tool name · task picker · All options · ⌘K │
│  sidebar)    ├──────────────────────────────────────────────────────┤
│              │  Task header: glyph tile, title, one-line summary    │
│ Search ⌘K    │                                                      │
│              │  ┌──────────────── Drop zone ────────────────────┐  │
│ Tools        │  │ thumbnail · name · size · Replace              │  │
│  ▣ ffmpeg    │  └────────────────────────────────────────────────┘  │
│  ▣ yt-dlp    │                                                      │
│  ▣ ...       │  Settings (grouped, label left, control right)       │
│              │   Size        [720p ▾]                               │
│ Recent       │   Quality     ───●──── Balanced                      │
│  ...         │   Remove sound [ ]                                   │
│              │   ▸ Extra arguments                                  │
│ + Add a tool │                                                      │
│              │  ┌──── Result card (after a run) ─────────────────┐  │
│              │  │ thumbnail · name · 86 MB (−93%) · Open Reveal  │  │
│              │  └────────────────────────────────────────────────┘  │
│              │ ╭─ Command bar (Liquid Glass, pinned to bottom) ───╮ │
│              │ │ ffmpeg -i holiday.mov -crf 23 …   ⧉   [ Run ⌘R ] │ │
│              │ ╰──────────────────────────────────────────────────╯ │
└──────────────┴──────────────────────────────────────────────────────┘
```

- **Sidebar:** the system's glass sidebar. Rows show a 22 pt rounded glyph tile in the tool's tint, then the
  name. A missing tool shows a small "Not installed" caption, and the row stays selectable.
- **Tool home:** when a tool is selected with no task, show a gallery of task cards: symbol, title and summary,
  in a 2 or 3 column grid. Hover lifts a card slightly. Clicking a card opens the task.
- **Task workspace:** content column centered with a maximum readable width of about 720 pt, scrolling
  under the pinned command bar.
- **Command bar:** a Liquid Glass capsule floating at the bottom. On the left is the syntax-colored command
  in SF Mono, truncated in the middle, with the full text in a popover on click. Then Copy, then the
  primary Run button in signal orange. While running, it morphs into progress (determinate when the tool
  reports it, otherwise an indeterminate bar), elapsed time, a "Show output" toggle and Cancel.
- **Output:** a collapsible console panel above the command bar, with monospaced, selectable text that
  auto-scrolls unless the user scrolls up.
- **Result card:** appears with a spring after success. It shows a Quick Look thumbnail, the file name, the
  size and its change from the input ("−93%"), and Open, Reveal in Finder and Drag-out actions. Failure shows
  a calm card with the last useful error line and "Show output".
- **Command palette (⌘K):** a centered glass panel with a search field and results from every tool and task
  ("Shrink a video, ffmpeg"). Arrow keys and Return work as expected.
- **Not installed:** a centered panel with the tool's glyph, "ffmpeg isn't installed", the
  `brew install ffmpeg` command in a copyable well, and a "Check again" button.

## Type

The app uses the system font only. Size roles:
- Task title: 22 pt semibold
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
- Run: the Run button morphs into the progress bar (matched geometry), with no layout jump.
- Done: the result card springs up from the command bar, and the symbol does one `bounce`.
- Respect Reduce Motion: use crossfades instead of movement.

## Website

The same brand, translated to the web: warm paper background, graphite text, signal orange used sparingly,
a distinctive display face for headlines with a clean grotesk for body text and a mono for commands. The
signature moment is an interactive demo: turn a real dial or move a slider, and a command line rewrites
itself live, showing the core idea in five seconds. Study premium Mac app sites (Raycast, Linear,
CleanShot, Things, Arc) for craft and restraint. Don't copy any of them.

## Review checklist

Judge each screen in light and dark mode at the minimum window size (900 × 620) and at a large size:

- [ ] One obvious primary action; signal orange appears nowhere else on the screen
- [ ] Alignment holds on the 4 pt grid; labels and controls share consistent columns
- [ ] Nothing truncates awkwardly, overlaps, or jumps when the state changes
- [ ] All states for this screen exist and read in plain words
- [ ] The command preview matches what actually runs (it's rendered from the same argv)
- [ ] Every control has an accessibility label; tab order follows reading order; the keyboard shortcuts work
- [ ] Contrast is comfortable in both modes, and nothing relies on color alone
- [ ] Motion is subtle, and Reduce Motion is respected
- [ ] It looks at home next to Apple's own apps on macOS 26, and better than most third-party ones
