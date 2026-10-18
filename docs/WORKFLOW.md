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

## Releasing (from M9 on)

`scripts/release.sh 0.1.0` does the following on this Mac. It checks first that `project.yml` and
`CHANGELOG.md` both name the version.
1. Runs `scripts/ci.sh release`, which also builds the Release app.
2. Signs the app with the Developer ID Application certificate and the hardened runtime.
3. Submits it with `xcrun notarytool submit --keychain-profile knobs-notary --wait`, then staples it.
4. Builds the DMG with `hdiutil`, then signs, notarizes and staples the DMG too.
5. Writes `dist/Knobs-0.1.0.dmg` and its SHA-256.
6. Prints the `gh release create` command for Deva to run. It doesn't run it.

Without the certificate it skips steps 2 to 4 and leaves an unsigned DMG, saying so. Without the notary
profile it signs but doesn't notarize, and says so.

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
