# Workflow

How work happens in this repo. It's written for a solo developer working with AI agents (Claude Code,
Codex) that may work unattended for long stretches.

## Hard rule: no hosted CI

Nothing runs on GitHub Actions or any other hosted CI. Deva lost about $250 on Actions minutes. All checks,
builds and releases run on this Mac through `scripts/`. `scripts/ci.sh` fails if a `.github/workflows`
folder ever appears. Uploading a finished release with `gh release create` is fine: it's an upload, not
Actions.

## Local CI

| Command | When | What it runs |
|---|---|---|
| `scripts/ci.sh fast` | Automatically before every commit (pre-commit hook) | No-hosted-CI check, format lint, KnobsCore unit tests |
| `scripts/ci.sh` | Before checking a box in PLAN, and before every push (pre-push hook) | Everything in `fast`, integration tests, app build with warnings as errors |
| `scripts/ci.sh release` | Before a release | Everything above, plus a Release build, and a failure if any of the 10 tools is missing |
| `scripts/ci.sh linux` | After changing KnobsCore, and before a Linux build | Format lint, then every library built and KnobsCore's unit tests run on Linux in a local container (OrbStack or Docker on this Mac; `swift:6.2-noble` unless `KNOBS_LINUX_IMAGE` names another). Never a hosted runner |
| `scripts/linux.sh build` | After changing anything in `linux/` | Builds the Linux app with warnings as errors in the local `knobs-linux-dev` container. `scripts/linux.sh run` then shows it at `http://localhost:8085` through GTK's Broadway backend, and `stop` ends it |
| `scripts/linux.sh package <version> [arm64\|amd64]` | Before handing out a Linux build | Builds release binaries in the Ubuntu 26.04 and Fedora 44 containers (the other architecture runs emulated) and writes `dist/linux/knobs_<version>_<arch>.deb`, `knobs-<version>-1.fc44.<arch>.rpm` and `knobs-<version>-linux-<arch>.tar.gz`; amd64 also writes `knobs-gui-bin-<version>-1-x86_64.pkg.tar.zst` for Arch, and its AUR `PKGBUILD` and `.SRCINFO` to `dist/linux/aur/`. Install-test each in a clean container of its distribution and run a task through Broadway before calling it done |

Test conventions the script relies on:
- Any suite that launches a real tool must be named `...IntegrationTests` (for example `FFmpegIntegrationTests`). `fast` skips suites matching `IntegrationTests`.
- Integration tests skip, with a message, when their tool isn't installed. With `KNOBS_REQUIRE_TOOLS=1` (set by `release` mode) they fail instead.

Hooks live in `scripts/hooks/` and are turned on with `scripts/install-hooks.sh`. That script sets
`core.hooksPath`, so the hooks are versioned files, not copies. Never skip them with `--no-verify`.

## Git

- One branch: `main`. A solo developer doesn't need feature branches. Use a short-lived branch only for an
  experiment that may be thrown away.
- Small commits, one concern each. Structural changes (rename, move, reformat) and behavior changes never
  share a commit.
- Message format: `area: why`, for example `core: keep values with spaces as one argument`.
  Areas: `core`, `app`, `manifests`, `scripts`, `docs`.
- Stage named paths. Never `git add -A` or `git add .`.
- Agents commit locally. Agents never push and never create remote repos. Deva pushes.
- Releases are tags: `v0.1.0`. Version numbers follow SemVer, and `CHANGELOG.md` gets an entry per release.

## Definition of done (for any task)

1. The behavior has tests through the public interface (KnobsCore), or a written manual check (app UI).
2. `scripts/ci.sh` passes in this session, and the output was read.
3. The affected docs are updated in the same commit: PLAN boxes, STATUS, MANIFEST_FORMAT, README.
4. A WORKLOG entry is appended with `scripts/log.sh`.
5. The work is committed.

## Unattended runs (goal mode)

An agent working alone loops through this:

1. Read `docs/STATUS.md`, then the last entries of `docs/WORKLOG.md`, then `docs/PLAN.md`. Run `git status`
   and `git log -5` to reconcile against reality, since a crash may have cut off the last log entry.
2. Take the first unchecked item in PLAN. Write the four lines from CLAUDE.md (outcome, evidence,
   boundaries, stop condition) into the WORKLOG entry for it.
3. Build it in small steps, running `scripts/ci.sh fast` after each one.
4. When it's done, follow the definition of done above.
5. If the same problem defeats two attempts: record it in `docs/BUGS.md`, mark the item blocked in STATUS,
   and move on to the next item that doesn't depend on it. Don't wait for an answer.
6. Questions for Deva go under "Waiting on Deva" in STATUS. Work continues on everything else.
7. Checkpoint the WORKLOG at least every hour, even mid-task.

Things an unattended agent never does: push, create or change remote repos, publish a release, change
GitHub settings, use `sudo`, delete files outside the repo, download anything other than Homebrew formulas
and the files listed in DECISIONS, or enter credentials.

## Publishing the website (Deva runs this; DEC-018)
The site is static files in `website/`. It goes to Cloudflare Pages by direct upload from this Mac, with no
hosted CI:

```bash
npx wrangler pages deploy website --project-name knobs
```

The first run asks Wrangler to sign in to Cloudflare in the browser and creates the `knobs` project. Check the
printed URL in a browser at desktop and phone widths before pointing a domain at it.
Once the address is known, add the link-preview image tags listed in `website/README.md` and deploy again.

## Releasing (from M9 on)

`scripts/release.sh 0.1.0` does the following on this Mac. It checks first that `project.yml` and
`CHANGELOG.md` both name the version.
1. Runs `scripts/ci.sh release`, which also builds the Release app.
2. Signs the app with the Developer ID Application certificate and the hardened runtime.
3. Submits it with `xcrun notarytool submit --keychain-profile knobs-notary --wait`, then staples it.
4. Builds the DMG with `diskutil image create`, then signs, notarizes and staples the DMG too.
5. Writes `dist/Knobs-0.1.0.dmg` and its SHA-256.
6. Prints the `gh release create` command for Deva to run, with the DMG and the same version's Linux packages
   from `dist/linux/`. It doesn't run it. Before that it checks the website: the version in
   `website/index.html`'s `#release` block must match, and every file it links to must be in `dist/`.

Without the certificate it skips steps 2 to 4 and leaves an unsigned DMG, saying so. Without the notary
profile it signs but doesn't notarize, and says so.

After the release is on GitHub, Deva pushes `dist/linux/aur/PKGBUILD` and `.SRCINFO` to the AUR's
`knobs-gui-bin` repository (`ssh://aur@aur.archlinux.org/knobs-gui-bin.git`, branch `master`). Not before: that
PKGBUILD downloads the release's x86_64 tarball and checks it against the checksum it carries. A change to the
PKGBUILD alone, with the same tarball, raises `pkgrel` instead of the version.

One-time setup only Deva can do:
- Create a **Developer ID Application** certificate: Xcode → Settings → Accounts → your team → Manage
  Certificates → + → Developer ID Application.
- Store notarization credentials:
  `xcrun notarytool store-credentials knobs-notary --apple-id <your Apple ID> --team-id P564YR8496`
  It prompts for an app-specific password, which you create at account.apple.com.

## Manual app check (until UI tests exist)

Before checking an app milestone, launch the built app and confirm:
- the tool list shows every manifest, and missing tools show the install command
- a task runs end to end on a real file, and the output appears next to the input
- Cancel stops a running task within 2 seconds
- the window works in light mode, dark mode, and with the keyboard only

Save a screenshot to `docs/screenshots/` and mention it in the WORKLOG entry.
