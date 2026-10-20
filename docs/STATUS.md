# Status

Editable snapshot of where things stand. The history lives in `docs/WORKLOG.md`.

Updated: 2026-10-20 IST (PDF tools: qpdf, img2pdf and Poppler added; AUR registration closed 22:35; website live 22:25; DMG install checked 22:22; AUR package ready 22:08; v0.1.0 released 21:45; pushed to GitHub 21:42; commit email rewritten 21:39; signed and notarized DMG 21:34; Developer ID certificate 21:22; publish steps checked 21:14)

## Now
- PDF tools for the next release (PLAN M12, Deva's request 2026-10-20): qpdf added, with golden tests and an
  integration test that runs all five tasks on a real PDF; img2pdf added, its integration test turning a JPEG
  and a transparent PNG into a two-page A4 PDF; Poppler's pdftoppm (a page as a PNG or JPEG) and pdftotext
  (a PDF's text into a .txt file) added, each run on a real PDF by its integration test. Still to do: a check
  of each in the app. Waiting on Deva: whether pdftoppm also gets "every page as images" (see Waiting on Deva). `website/` already lists them (its test keeps the gallery in
  step with the manifests), but the live site describes 0.1.0, so deploy `website/` with the next release, not
  before. BUG-017 (open): qpdf's All options shows colon-suffixed flags qpdf rejects, and img2pdf's misreads
  `--pagesize` and `--imgsize`; the tasks are fine.
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
- Release files include the review fixes and the BUG-014 fix (the code is unchanged since dac2af0):
  - Signed and notarized Mac DMG (2026-10-20, 21:34 IST): Deva ran `scripts/release.sh 0.1.0` in the main
    checkout. `scripts/ci.sh release` PASS (160 tests in 27 suites, Debug and Release app builds); the app and
    the DMG were each signed with "Developer ID Application: DEVAPRASAD T P (P564YR8496)", accepted by Apple's
    notary service and stapled; the script's website check found every `#release` file in `dist/`. Checked
    afterwards: `spctl` accepts the DMG and the app inside it as "Notarized Developer ID", `stapler validate`
    passes on both, `codesign --verify --deep --strict` passes, the app has the hardened runtime and no
    entitlements, `syspolicy_check distribution` says it is ready for distribution, and the SHA-256 file
    matches (9da1de32...). Installed by hand (22:22 IST): the DMG downloaded from the GitHub release and marked
    as a browser download (quarantine), Knobs dragged to /Applications in Finder, then opened: it started with
    no Gatekeeper prompt or warning, macOS marked it approved (quarantine flag 0183 to 01c3), and its window
    showed the tool list. That is PLAN M9's exit check.
  - All seven Linux packages (`scripts/linux.sh package 0.1.0` arm64 and amd64), each installed in a clean
    container and run through Broadway: Shrink a video on the 36.3 MB 1080p sample gave a 10 s 1280x720
    H.264+AAC file and "Done in N s" every time. arm64 .deb (Ubuntu 26.04), .rpm (Fedora 44, GTK 4.22.5,
    swift-lang-runtime 6.3.2) and tarball; x86_64 .deb, .rpm, tarball and Arch `knobs-bin` (GTK 4.24.1,
    libadwaita 1.10.0) under emulation. Under emulation GNU tar 1.35 can't unpack anything ("Function not
    implemented") and pacman needs `--disable-sandbox`; both are OrbStack/Rosetta limits, so the x86_64 tarball
    was unpacked with bsdtar. None of these were tried on a real x86_64 machine.
- Review fixes (2026-10-19): all ten findings of the full code review are fixed, one commit each (d1ed5a4,
  75161d5, b95fd27, ac258ba, cb0acc6, 74ca5f3, 3787282 with 911e759, d1c75cd, 4340d06, 989f83f). Both apps now
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

- Published 2026-10-20: the repository, release v0.1.0, and the website at https://knobs.pages.dev. Agents now
  push `main` themselves (DEC-020).
  - Website (22:25 IST, deployed by me on Deva's request): Cloudflare Pages project `knobs`, production branch
    `main`. Checked: `/` and every asset 200 with the same bytes as `website/`, an unknown path gets our 404
    page with status 404, the four `_headers` security headers are set, no console errors in a browser, and the
    Download buttons and GitHub links point at the v0.1.0 release. On the way, Wrangler's `pages project create`
    deployed a Worker `knobs` at knobs.bitdeva.workers.dev (Deva's Gmail name in the address) for about nine
    minutes, serving only `website/`'s files (repo files, docs, `dist/` and `.git` were 404). Deva chose Pages;
    that Worker, which had only my one deployment, was deleted and its address returns 404. Nothing else in the
    Cloudflare account was touched.
  - Release v0.1.0 (21:45 IST): Deva created it at b08ddd3 with the notes in `dist/release-notes-0.1.0.md`
    (written from CHANGELOG, gitignored). Checked: published, not a draft; all nine files (DMG, its .sha256,
    seven Linux packages) have the same SHA-256 on GitHub as in `dist/`; every `#release` download link and the
    site's four GitHub links answer 200.
  - Repository (21:41 IST): Deva created the public github.com/deva0x/knobs, turned GitHub Actions off before
    the first push, and pushed `main` (the pre-push hook ran `scripts/ci.sh` full: PASS). Checked through the
    GitHub API: Actions disabled with 0 runs, Dependabot alerts and code scanning default setup off, every
    author and committer email 95619082+deva0x@users.noreply.github.com (Deva's choice; the history was
    rewritten at 21:39, WORKLOG maps old to new hashes), commits linked to the deva0x account, no token, key or
    `/Users/deva` path in any commit. The pre-rewrite commits stay on this Mac under `refs/original/`; GitHub
    never got them, and Deva can delete them.

## Waiting on Deva
Decisions DEC-010 and DEC-015 and BUG-012's choice are taken (DEC-018). What is left needs Deva's accounts or a
system setting:
1. AUR account: register at aur.archlinux.org and add an SSH public key under My Account (agents may not create
   accounts). Blocked on the AUR's side: on 2026-10-20 at 22:35 IST registration answered HTTP 503, "New account
   registration is temporarily closed" (a wave of automated sign-ups; no date given, no manual queue). The Arch
   news feed had no notice yet; updates come there and on aur-general. Try again by hand later, never by script.
   Until then Arch users install the release's `knobs-bin` package, as the website's Arch tab says. Then an agent publishes `knobs-gui-bin` (DEC-019, DEC-020): clone
   `ssh://aur@aur.archlinux.org/knobs-gui-bin.git`, set that clone's user.email to the GitHub private address,
   add the PKGBUILD and .SRCINFO, commit, push `master`. The files for 0.1.0 are in this worktree's
   `dist/linux/aur/` (`.claude/worktrees/where-are-we-e513b3`); any checkout can write them again with the amd64
   `scripts/linux.sh package` or `linux/packaging/package-arch.sh`. Tested 2026-10-20 in a fresh archlinux
   container given only the PKGBUILD: makepkg downloaded the tarball from the release and its checksum passed
   (it equals GitHub's digest), `makepkg --printsrcinfo` matches the .SRCINFO, namcap reports nothing on the
   PKGBUILD and no errors on the package, pacman installed it with GTK and libadwaita, no library is missing,
   `knobs --help` runs, and its 16 files are byte-identical to the tested 0.1.0 `knobs-bin` apart from the
   license folder's name.
2. Domain: Deva is buying one on Cloudflare for the site. Once it is attached to the Pages project `knobs`, an
   agent adds the link-preview image tags with that address (website/README.md, "Link previews"), deploys
   again, and changes the website link in the GitHub repository's About box and in README's Download section
   from https://knobs.pages.dev to the domain.
3. pdftoppm "every page as images": pdftoppm can only write `<name>-1.png`, `<name>-2.png` and so on into a
   folder, replacing files of the same names, and it can't make a new folder, so the task would break the
   "Nothing is overwritten" promise (SECURITY.md, README). Either accept that for this one task and list it
   under SECURITY.md's Known limits, or extend the manifest format so an output can be a new folder Knobs
   makes before the run (as 7-Zip's Extract gets from 7-Zip itself), in KnobsCore and both apps.
4. Optional: try Reduce Motion, VoiceOver and keyboard-only use once on the Mac (PLAN M9's accessibility item;
   each needs a system setting, and Keyboard navigation is off on this Mac), click through Knobs on omarchy-1,
   and export a .p12 backup of the Developer ID certificate (created 2026-10-20 21:22 IST through Xcode; its
   private key is only in this Mac's login keychain).

## Blocked
- Nothing. BUG-009 is fixed (see BUGS).
