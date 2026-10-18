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
  main.js           links, the demo's command builder, the dial, the extra-arguments splitter, copy buttons
  assets/
    favicon.svg     the dial mark
    screenshots/    real app screenshots go here (empty for now)
```

## Where things live

- **Links:** the GitHub, download, manifest-format and license URLs are set once in `LINKS` at the top of
  `main.js` and applied to every `[data-link]` element. Without JavaScript those links fall back to the
  download section of the page.
- **Demo command:** `main.js` holds the Shrink a video task in manifest form (`SHRINK_VIDEO`, copied from
  `docs/MANIFEST_FORMAT.md`) and builds the command from it with the same rules the app follows: conditionals,
  `{field.stem}`-style placeholders, `{extra}` and `{output}`. If the ffmpeg manifest changes, update it here too.
- **Tool tasks:** the gallery lists tasks from `docs/PLAN.md` (M6). Keep them in step with the real manifests.

## Real screenshots

The hero currently shows an HTML/CSS recreation of the app window inside
`<figure class="shot" data-screenshot-slot="hero">`. The comment above that figure in `index.html` has the
exact `<picture>` markup to use instead (light and dark versions). Save images in `assets/screenshots/`,
at 2x, and keep each one under about 300 KB.

## Hosting

Not decided, and nothing is deployed. GitHub Pages builds run on GitHub Actions, which this project doesn't
use (DEC-002), so a direct upload from this Mac is the likely route, for example Cloudflare Pages with
`wrangler pages deploy website`. Deva chooses the host (PLAN M10).
