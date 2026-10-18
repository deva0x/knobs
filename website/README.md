# Knobs website

A single static page. Plain HTML, CSS and JavaScript: no build step, no framework, no npm.
The only outside request is Google Fonts (Archivo and IBM Plex Mono). There's no analytics and no CDN.

## Preview locally

Open `index.html` directly in a browser, or serve the folder:

```bash
cd website
python3 -m http.server
```

Then visit http://localhost:8000.

## Files

```
website/
  index.html        the page: hero, dial demo, tools, three layers, safe by design, manifests, download, FAQ
  styles.css        all styles; colors are custom properties on :root, with dark values under prefers-color-scheme
  main.js           links, downloads and the Linux chooser, the demo's command builder, the dial, the
                    extra-arguments splitter, copy buttons
  assets/
    favicon.svg            the dial mark
    screenshots/           real app screenshots, light and dark: the Mac hero and the Linux card
```

## Where things live

- **Links:** the GitHub, releases-page, manifest-format and license URLs are set once in `LINKS` at the top of
  `main.js` and applied to every `[data-link]` element. Without JavaScript those links fall back to the
  download section of the page.
- **Downloads:** the release's version and exact file names live in the page's
  `<script type="application/json" id="release">`. `main.js` builds the Mac button's link and the Linux chooser
  (distribution, processor, file, install command) from it, and on Linux makes the hero's first button a Linux
  one. For a new release, update that block; `scripts/release.sh` stops if its version doesn't match or any file
  it names is missing from `dist/`.
- **Demo command:** the page holds the real Shrink a video task in `<script type="application/json" id="demo-task">`,
  copied exactly from `Manifests/ffmpeg.json`. `main.js` builds the demo's command from it with the same rules the
  app follows: conditionals, `{field.stem}`-style placeholders, `{extra}` and `{output}`. The safety example, the
  manifest excerpt and the small window in the manifests section show the same task by hand.
- **Tool tasks:** the gallery's tool names, tasks and brew formulas come from `Manifests/`.
- **Kept in step by tests:** `WebsiteTests` (run by `scripts/ci.sh fast`) fails when `#demo-task` differs from the
  manifest or the gallery names a tool, task or formula the manifests don't have. Update the page when a manifest
  changes.

## Real screenshots

The hero shows real app screenshots, `assets/screenshots/hero-light.jpg` and `hero-dark.jpg`, picked by the
reader's light or dark setting. They are window captures of Shrink a video (`screencapture -o -l <window id>`)
from the Debug app with a fresh data folder, saved at 1760 px wide as JPEG and kept under about 300 KB. Retake
both when the task screen changes.

The Linux card shows `linux-light.jpg` and `linux-dark.jpg`: the Linux app's Shrink a video, ready to run, taken
in a local container through GTK's Broadway backend with GNOME's Adwaita Sans font, the tools installed from
Ubuntu's archive, and `ADW_DEBUG_COLOR_SCHEME=prefer-dark` for the dark one. Headless Chrome drew the Broadway
page at 1440 × 833 and twice the pixels; the capture was cropped to 1500 px high and saved at 1760 px wide.
The video's path is `/home/alex/Videos/Sunset over Goa.mov`, a made-up home folder, never a real one.

## Hosting

Cloudflare Pages by direct upload from this Mac (DEC-018), no hosted CI. Deva runs the deploy; see
`docs/WORKFLOW.md`, "Publishing the website". Nothing is deployed yet.
