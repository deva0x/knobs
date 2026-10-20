# Status

Editable snapshot of where things stand. The history lives in `docs/WORKLOG.md`.

Updated: 2026-10-20 IST (publish steps checked 21:14; release files rebuilt 2026-10-19 08:36)

## Now
- Done: M0 to M3, three code review rounds, the macOS redesign (task stage, inspector, tool home), real
  screenshots in the README and on the website, and most of the Linux version (M11).
- Website (2026-10-19), ready to deploy: the demo, safety example and manifest excerpt show the real Shrink a
  video task (WebsiteTests keep it and the tool gallery in step with the manifests); direct Mac and Linux
  downloads from one `#release` block, with a Linux chooser (distribution, processor, install command) that
  `scripts/release.sh` checks against `dist/`; real Linux screenshots; a 404 page, Cloudflare headers, a
  home-screen icon and a link-preview image. Checked in a browser at 320, 375, 768, 940, 980, 1100, 1280 and
  1440 px, light and dark, by keyboard, and with JavaScript off; no console errors. `scripts/ci.sh linux`
  passes with the website tests (151 tests after the BUG-014 fix).
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
    window; their arm64 twins ran the real tasks. Since the 08:00 rebuild all x86_64 packages ran Shrink a video
    too (see Release below).
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
- Release files rebuilt from 78fbd9d (2026-10-19, 08:01-08:36 IST), so they include the review fixes and the
  BUG-014 fix:
  - `scripts/release.sh 0.1.0`: `scripts/ci.sh release` PASS (160 tests in 27 suites with every tool required,
    Debug and Release app builds), then an unsigned `dist/Knobs-0.1.0.dmg` (hdiutil verify: valid; SHA-256 file
    matches). Signing and notarizing need Deva's certificate and notary profile. An unsigned run stops before
    the website link check, so it was run by hand: all eight files `#release` links to are in `dist/`.
  - All seven Linux packages (`scripts/linux.sh package 0.1.0` arm64 and amd64), each installed in a clean
    container and run through Broadway: Shrink a video on the 36.3 MB 1080p sample gave a 10 s 1280x720
    H.264+AAC file and "Done in N s" every time. arm64 .deb (Ubuntu 26.04), .rpm (Fedora 44, GTK 4.22.5,
    swift-lang-runtime 6.3.2) and tarball; x86_64 .deb, .rpm, tarball and Arch `knobs-bin` (GTK 4.24.1,
    libadwaita 1.10.0) under emulation. Under emulation GNU tar 1.35 can't unpack anything ("Function not
    implemented") and pacman needs `--disable-sandbox`; both are OrbStack/Rosetta limits, so the x86_64 tarball
    was unpacked with bsdtar. None of these were tried on a real x86_64 machine.
- Review fixes (2026-10-19): all ten findings of the full code review are fixed, one commit each (2eba140,
  83ba95c, ad4fcd2, 7cbaba1, 8e64330, 8e23f01, 2de4704 with eeef184, eb2dea4, 3109b9c, 55a1584). Both apps now
  share one `Toolbox` (KnobsSession), tested by the new KnobsSessionTests. On Linux, closing the window during a
  run asks first (Keep Running, or Stop and Close), and a run redraws the window only when something changed
  (839 redraws down to 418 on the same Shrink a video run). `scripts/ci.sh` full passes (159 tests in 27
  suites plus 2 Toolbox tests, app build).
- BUG-014 fixed (2026-10-19): each output pipe is read with a blocking loop on its own thread, on both
  platforms, so Linux gets all of a tool's output. `scripts/ci.sh fast`, `scripts/ci.sh` full (160 tests in 27
  suites plus 2, app build) and `scripts/ci.sh linux` (151 tests, one known issue: BUG-016) pass.
- BUG-016 (new, open, older than the fix): on Linux, a tool that leaves a helper running looks unfinished until
  the helper exits, because Foundation's `Process` reports the exit late. Cancel still stops it.
- BUG-015 (Linux libdispatch crash after a run stops) not seen after the fix: 23 Run → Cancel cycles and 5 Stop
  and Close trials through Broadway, with backtraces on, no crash. Kept open because it was rare before too.
- Upstream (2026-10-19): BUG-014 reported as swiftlang/swift-corelibs-foundation#5618; BUG-015's crash matches
  #3276 and BUG-016 is #4795, both already open there.
- Next action: none for BUG-014. Watch for BUG-015 in later Linux checks; BUG-016 needs a Linux `Process`
  replacement or an upstream fix, not planned.

## Waiting on Deva
Decisions DEC-010 and DEC-015 and BUG-012's choice are taken (DEC-018). What is left needs Deva's accounts, a
publish, or a system setting:
1. Create the Developer ID Application certificate and store the notary profile `knobs-notary` (WORKFLOW,
   "Releasing"); `scripts/release.sh` then signs and notarizes instead of building an unsigned DMG.
   Checked 2026-10-20: Xcode is signed in to team P564YR8496 and has its Apple Development and Apple
   Distribution certificates, but there is no Developer ID Application certificate and no `knobs-notary`
   profile. Only the team's Account Holder sees Developer ID Application under Manage Certificates → +, and
   Apple allows only a few per team, so export a .p12 backup of it. The release script's signing half was
   read and tried on an ad-hoc copy: the app has one executable and nothing nested to sign first, and
   re-signing drops the debug-only `get-task-allow` entitlement that notarization refuses.
2. Create the GitHub repository `deva0x/knobs`, turn off GitHub Actions for it before the first push, and push.
   Then create release v0.1.0 with the DMG and the `dist/linux/` files (`scripts/release.sh` prints the
   command). The website's Download buttons link straight to that release's files (`#release` in
   website/index.html); only "Every file of this release" goes to the latest-release page.
   In that order: `gh repo create deva0x/knobs --public` without `--source` or `--push` (either would push
   before Actions is off), then `gh api -X PUT repos/deva0x/knobs/actions/permissions -F enabled=false`, then
   add the remote and push `main`. Before the release, date CHANGELOG's `[0.1.0] - not yet released`.
   Checked 2026-10-20: no token, key or `/Users/deva` path in any commit, no `.github` folder, the biggest file
   is a 1 MB screenshot. All 105 commits name bitdeva@gmail.com as author, which becomes public; if GitHub's
   "Block command line pushes that expose my email" is on, GitHub refuses the push.
3. Deploy the website (WORKFLOW, "Publishing the website"), then add the link-preview image tags with the
   site's address (website/README.md, "Link previews") and deploy again. Checked 2026-10-20: Wrangler is signed
   in to one Cloudflare account with Pages write access, and no Pages project exists yet, so the first deploy
   creates `knobs`. Wrangler leaves a `.wrangler/` cache in the repo, now ignored.
4. Optional: publish `knobs-bin` to the AUR (needs an AUR account and a public link to the x86_64 tarball).
5. Optional: try Reduce Motion, VoiceOver and keyboard-only use once on the Mac (PLAN M9's accessibility item;
   each needs a system setting, and Keyboard navigation is off on this Mac), and click through Knobs on
   omarchy-1.

## Blocked
- Nothing. BUG-009 is fixed (see BUGS).
