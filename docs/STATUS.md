# Status

Editable snapshot of where things stand. The history lives in `docs/WORKLOG.md`.

Updated: 2026-10-18 IST

## Now
- Done: M0 to M3. Most of M4 to M9 is built; see the boxes in PLAN. Code review round 1 is done and its fixes
  are committed (WORKLOG, 15:36 IST); round 2 is reviewing the round-1 diff.
- Verified in the app on this Mac (earlier): ffmpeg Shrink a video (21.2 MB to 1.6 MB, checked with ffprobe),
  ExifTool Show hidden details, ImageMagick Compress, All options for ffmpeg, Add a Tool with `jq`, Go to Task
  (⌘K), the Open With chooser, and the large link field on yt-dlp Download a video (seen with Paste and the
  folder icon; typing a link and Run becoming enabled is not checked yet).
- Verified by tests: `scripts/ci.sh` full passes (139 tests, every task of all ten tools running for real).
- Verified by rendering: the layered app icon (`App/AppIcon.icon`) as the built app shows it, light and dark.
- Built but not yet seen on screen (the screen has been locked): the About window, the icon in the Dock, the
  quit-while-running dialog, Reduce Motion crossfades, the console's stop-following on scroll, and every view
  change from the round-1 review.
- Open milestone exits:
  - M4/M5: the light-and-dark UI review loop across every screen, and final screenshots in `docs/screenshots/`.
  - M5: renaming presets is built and unit tested; check it on screen.
  - M6: run each of the other seven tools once in the app (their integration tests pass).
  - M8: real app screenshots on the website.
  - M9: accessibility pass with VoiceOver; `scripts/ci.sh release`; a signed DMG needs Deva's certificate.
- Next action: finish code review round 2; then, when the screen is available, the UI pass (everything listed
  above as not yet seen), final screenshots, and the website screenshots.

## Waiting on Deva
1. Create the Developer ID Application certificate (see WORKFLOW, "Releasing"). Only Apple Development and
   Apple Distribution identities are in the keychain now, so `scripts/release.sh` builds an unsigned DMG.
2. Store the notary profile `knobs-notary` (see WORKFLOW).
3. Decide the final name, license and bundle id before publishing (DEC-010, M10). The About window and the
   website use the working repo address `github.com/deva0x/knobs`.
4. Create the GitHub repo, turn off GitHub Actions for it before the first push, and push (M10).
5. Choose where the website is hosted (M10).

## Blocked
Nothing. No open bugs (BUG-001 is fixed).
