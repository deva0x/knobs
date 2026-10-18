# Status

Editable snapshot of where things stand. The history lives in `docs/WORKLOG.md`.

Updated: 2026-10-18 IST

## Now
- Done: M0 to M3, three code review rounds, the macOS redesign (task stage, inspector, tool home), real
  screenshots in the README and on the website, and the Linux slice (M11). Open boxes are in PLAN.
- Verified in the Mac app on this Mac: ffmpeg Shrink a video, Compress an image, a failing run, the Open With
  chooser, link and folder tasks, All options, Add a Tool with `jq`, ⌘K, in light and dark.
- Verified by tests: `scripts/ci.sh` full passes (every task of all ten tools running for real); `scripts/ci.sh
  linux` passes on Ubuntu 24.04 and 26.04 containers.
- Linux (M11): the app runs in a local container and was checked through GTK's Broadway backend (a real ffmpeg
  run, Cancel, settings remembered). In progress: .deb and .rpm packages (`scripts/linux.sh package`), and All
  options with a settings search on Linux. Neither is install-tested yet.
- Not yet seen on screen (Mac): preset rename through the toolbar menu, drag and drop onto the tool home,
  Reduce Motion, real VoiceOver, the About window, the quit-while-running dialog.
- Release: `scripts/ci.sh release` passes and `scripts/release.sh 0.1.0` builds an unsigned DMG; signing and
  notarizing need Deva's certificate and notary profile.
- Next action: build both Linux packages, install each in a clean Ubuntu 26.04 and Fedora 44 container and run
  Shrink a video through Broadway (the M11 exit), then check All options on Linux the same way.

## Waiting on Deva
1. Create the Developer ID Application certificate (see WORKFLOW, "Releasing"). Only Apple Development and
   Apple Distribution identities are in the keychain now, so `scripts/release.sh` builds an unsigned DMG.
2. Store the notary profile `knobs-notary` (see WORKFLOW).
3. Decide the final name, license and bundle id before publishing (DEC-010, M10). The About window and the
   website use the working repo address `github.com/deva0x/knobs`.
4. Create the GitHub repo, turn off GitHub Actions for it before the first push, and push (M10).
5. Choose where the website is hosted (M10).
6. Linux packaging (DEC-015). The GTK library Knobs uses on Linux needs GTK 4.20+, so .deb and .rpm work on
   Ubuntu 26.04, Fedora 43 and newer only, and AppImage doesn't fit. Accept that floor, or un-defer Flatpak to
   also reach Ubuntu 24.04 LTS and Debian 13? I recommended AppImage before the spike showed this; that advice
   was wrong.

## Blocked
- BUG-009 (open, older than the redesign): opening a task in a different tool, from a Recent row or the file
  chooser, shows that tool's home instead of the task. Three fixes were tried and reverted; see BUGS for the
  evidence and the next idea. Within one tool everything works.
