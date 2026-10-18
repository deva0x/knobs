# Status

Editable snapshot of where things stand. The history lives in `docs/WORKLOG.md`.

Updated: 2026-10-18 IST

## Now
- Done: M0 to M3. Most of M4 to M9 is built; see the boxes in PLAN.
- Verified in the app on this Mac: ffmpeg Shrink a video (21.2 MB to 1.6 MB, checked with ffprobe), ExifTool
  Show hidden details, ImageMagick Compress, All options for ffmpeg, Add a Tool with `jq`, Go to Task (⌘K),
  the Open With chooser, and the new large link field on yt-dlp Download a video (seen with Paste and the
  folder icon; typing a link and Run becoming enabled is not checked yet).
- Verified by tests: every task of all ten tools runs for real in `ToolIntegrationTests` (`scripts/ci.sh`
  passed on 2026-10-18).
- Built but not yet seen on screen: the app icon in the Dock and Finder (check whether macOS 26 re-masks the
  legacy icon set and clips its shadow; an Icon Composer `.icon` may be needed), and the About window. The screen was
  locked, so these wait for the next UI pass.
- Open milestone exits:
  - M4/M5: the light-and-dark UI review loop across every screen, and final screenshots in `docs/screenshots/`.
  - M5: renaming presets (save, apply and delete work).
  - M6: run each of the other seven tools once in the app (their integration tests pass).
  - M8: real app screenshots on the website.
  - M9: accessibility pass; `scripts/ci.sh release`; a signed DMG needs Deva's certificate (below).
- Next action: when the screen is available, continue the UI review loop (whisper, rsync, 7-Zip, All options,
  light mode), take final screenshots, and put them on the website. Until then, the full code review.

## Waiting on Deva
1. Create the Developer ID Application certificate (see WORKFLOW, "Releasing"). Only Apple Development and
   Apple Distribution identities are in the keychain now, so `scripts/release.sh` builds an unsigned DMG.
2. Store the notary profile `knobs-notary` (see WORKFLOW).
3. Decide the final name, license and bundle id before publishing (DEC-010, M10). The About window and the
   website use the working repo address `github.com/deva0x/knobs`.
4. Create the GitHub repo, turn off GitHub Actions for it before the first push, and push (M10).
5. Choose where the website is hosted (M10).

## Blocked
Nothing. Open bugs: BUG-001 (Ghostscript and `%` in file names), low impact, has a workaround.
