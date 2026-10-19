# Status

Editable snapshot of where things stand. The history lives in `docs/WORKLOG.md`.

Updated: 2026-10-19 IST

## Now
- Done: M0 to M3, three code review rounds, the macOS redesign (task stage, inspector, tool home), real
  screenshots in the README and on the website, and most of the Linux version (M11).
- Website (2026-10-19), ready to deploy: the demo, safety example and manifest excerpt show the real Shrink a
  video task (WebsiteTests keep it and the tool gallery in step with the manifests); direct Mac and Linux
  downloads from one `#release` block, with a Linux chooser (distribution, processor, install command) that
  `scripts/release.sh` checks against `dist/`; real Linux screenshots; a 404 page, Cloudflare headers, a
  home-screen icon and a link-preview image. Checked in a browser at 320, 375, 768, 940, 980, 1100, 1280 and
  1440 px, light and dark, by keyboard, and with JavaScript off; no console errors. `scripts/ci.sh linux`
  passed with the website tests (140 tests) earlier on 2026-10-19; it now fails on BUG-014, see below.
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
  - BUG-013 fixed: a file chosen in the file dialog could arrive as a garbled path (a use-after-free in Adwaita
    for Swift); Knobs now opens GTK's dialog itself. All seven Linux packages were rebuilt with the fix on
    2026-10-19. The rebuilt aarch64 tarball, unpacked and started by the relative path the website gives,
    found all ten tools, and its folder picker fed rsync's Copy a folder, which copied for real.
  - Not yet: clicking through on a real Linux desktop.
- Seen on screen (Mac, 2026-10-19): preset save and rename through the toolbar menu, drag and drop onto a tool
  home (an image opens the chooser, a PDF is refused), the About window, the quit-while-running dialog (Keep
  Running continues, Stop and Quit stops ffmpeg and quits), and BUG-009's fix.
- Not checked by me (system settings I may not change): Reduce Motion and real VoiceOver.
- Release: `scripts/ci.sh release` passes and `scripts/release.sh 0.1.0` builds an unsigned DMG; signing and
  notarizing need Deva's certificate and notary profile.
- Review fixes (2026-10-19): all ten findings of the full code review are fixed, one commit each (2eba140,
  83ba95c, ad4fcd2, 7cbaba1, 8e64330, 8e23f01, 2de4704 with eeef184, eb2dea4, 3109b9c, 55a1584). Both apps now
  share one `Toolbox` (KnobsSession), tested by the new KnobsSessionTests. On Linux, closing the window during a
  run asks first (Keep Running, or Stop and Close), and a run redraws the window only when something changed
  (839 redraws down to 418 on the same Shrink a video run). `scripts/ci.sh` full passes (159 tests in 27
  suites plus 2 Toolbox tests, app build).
- Blocked: `scripts/ci.sh linux` fails on BUG-014 (Linux reads only the first 8 KB of a burst of output; older
  than the review fixes). BUG-015, an occasional libdispatch crash on Linux after a run stops, is probably the
  same cause.
- Next action: BUG-014: log each output read on Linux, then replace `readabilityHandler` in
  `ToolRunner.listen` if confirmed, and rerun `scripts/ci.sh linux` and the Broadway Cancel trial (BUG-015).

## Waiting on Deva
Decisions DEC-010 and DEC-015 and BUG-012's choice are taken (DEC-018). What is left needs Deva's accounts, a
publish, or a system setting:
1. Create the Developer ID Application certificate and store the notary profile `knobs-notary` (WORKFLOW,
   "Releasing"); `scripts/release.sh` then signs and notarizes instead of building an unsigned DMG.
2. Create the GitHub repository `deva0x/knobs`, turn off GitHub Actions for it before the first push, and push.
   Then create release v0.1.0 with the DMG and the `dist/linux/` files (`scripts/release.sh` prints the
   command). The website's Download buttons link straight to that release's files (`#release` in
   website/index.html); only "Every file of this release" goes to the latest-release page.
3. Deploy the website (WORKFLOW, "Publishing the website"), then add the link-preview image tags with the
   site's address (website/README.md, "Link previews") and deploy again.
4. Optional: publish `knobs-bin` to the AUR (needs an AUR account and a public link to the x86_64 tarball).
5. Optional: try Reduce Motion and VoiceOver once on the Mac, and click through Knobs on omarchy-1.

## Blocked
- Nothing. BUG-009 is fixed (see BUGS).
