# Status

Editable snapshot of where things stand. The history lives in `docs/WORKLOG.md`.

Updated: 2026-10-18 IST

## Now
- Done: M0 to M3, three code review rounds, the macOS redesign (task stage, inspector, tool home), real
  screenshots in the README and on the website, and most of the Linux version (M11).
- Verified in the Mac app on this Mac: ffmpeg Shrink a video, Compress an image, a failing run, the Open With
  chooser, link and folder tasks, All options, Add a Tool with `jq`, ⌘K, in light and dark.
- Verified by tests: `scripts/ci.sh` full passes (149 tests in 26 suites, every task of all ten tools running for
  real, Mac app build with warnings as errors; run 2026-10-18 19:00 IST). `scripts/ci.sh linux` passed earlier
  on Ubuntu 24.04 and 26.04 containers.
- Linux (M11), checked through GTK's Broadway backend in local containers:
  - The app: every field kind, Run, Cancel, remembered settings, All options with a settings search, Add a Tool
    and Remove (BUG-011 fixed on the way).
  - The .deb: installed in a clean Ubuntu 26.04 container, found its manifests and settings folder on its own,
    and ran Shrink a video (36.3 MB to 1.34 MB). 7-Zip is found as Ubuntu's `7z` (DEC-016) and made a valid ZIP.
  - The .rpm: installed in a clean Fedora 44 container (pulling in swift-lang-runtime and GTK 4.22) and ran
    Remove the sound. Shrink a video fails there with Fedora's `ffmpeg-free`, which lacks libx264 (BUG-012).
  - Not yet: x86_64 packages, a real desktop session (only Broadway), and typing speed in long option lists
    outside Broadway.
- Not yet seen on screen (Mac): preset rename through the toolbar menu, drag and drop onto the tool home,
  Reduce Motion, real VoiceOver, the About window, the quit-while-running dialog.
- Release: `scripts/ci.sh release` passes and `scripts/release.sh 0.1.0` builds an unsigned DMG; signing and
  notarizing need Deva's certificate and notary profile.
- Next action: x86_64 (amd64) packages through Rosetta containers, then the Mac on-screen items above
  (they need full-screen control, so they wait for Deva to approve it or check them)

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
7. Fedora and Shrink a video (BUG-012): keep pointing Fedora users to RPM Fusion's ffmpeg (done in the README),
   or teach manifests a fallback encoder so it works with Fedora's own ffmpeg-free (a quality slider becomes a
   bitrate setting there).

## Blocked
- BUG-009 (open, older than the redesign): opening a task in a different tool, from a Recent row or the file
  chooser, shows that tool's home instead of the task. Three fixes were tried and reverted; see BUGS for the
  evidence and the next idea. Within one tool everything works.
