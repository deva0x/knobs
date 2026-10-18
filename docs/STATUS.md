# Status

Editable snapshot of where things stand. The history lives in `docs/WORKLOG.md`.

Updated: 2026-10-19 IST

## Now
- Done: M0 to M3, three code review rounds, the macOS redesign (task stage, inspector, tool home), real
  screenshots in the README and on the website, and most of the Linux version (M11). The website offers both
  the Mac and the Linux downloads, with the requirements for each (checked at desktop and phone widths, light and
  dark, on 2026-10-19).
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
    Remove the sound, and Shrink a video once BUG-012 was fixed (H.264 through Fedora's own encoder).
  - Arch (DEC-017): the `knobs-bin` package installed in a clean archlinux container (GTK 4.24) and ran Shrink a
    video. The x86_64 build runs on a real Omarchy (Arch, Hyprland) desktop on Deva's omarchy-1; only looked at,
    not clicked through (no safe way to send clicks to a desktop someone may be using).
  - x86_64: the .deb and .rpm installed in clean x86_64 Ubuntu 26.04 and Fedora 44 containers and drew their
    window; their arm64 twins ran the real tasks.
  - Long option lists filter when typing pauses, so typing keeps up (checked through Broadway).
  - Not yet: clicking through on a real Linux desktop.
- Seen on screen (Mac, 2026-10-19): preset save and rename through the toolbar menu, drag and drop onto a tool
  home (an image opens the chooser, a PDF is refused), the About window, the quit-while-running dialog (Keep
  Running continues, Stop and Quit stops ffmpeg and quits), and BUG-009's fix.
- Not checked by me (system settings I may not change): Reduce Motion and real VoiceOver.
- Release: `scripts/ci.sh release` passes and `scripts/release.sh 0.1.0` builds an unsigned DMG; signing and
  notarizing need Deva's certificate and notary profile.
- Next action: nothing left that I can do without Deva; see below.

## Waiting on Deva
Decisions DEC-010 and DEC-015 and BUG-012's choice are taken (DEC-018). What is left needs Deva's accounts, a
publish, or a system setting:
1. Create the Developer ID Application certificate and store the notary profile `knobs-notary` (WORKFLOW,
   "Releasing"); `scripts/release.sh` then signs and notarizes instead of building an unsigned DMG.
2. Create the GitHub repository `deva0x/knobs`, turn off GitHub Actions for it before the first push, and push.
   Then create release v0.1.0 with the DMG and the `dist/linux/` files (`scripts/release.sh` prints the
   command); the website's Download buttons point at the latest release.
3. Deploy the website (WORKFLOW, "Publishing the website").
4. Optional: publish `knobs-bin` to the AUR (needs an AUR account and a public link to the x86_64 tarball).
5. Optional: try Reduce Motion and VoiceOver once on the Mac, and click through Knobs on omarchy-1.

## Blocked
- Nothing. BUG-009 is fixed (see BUGS).
