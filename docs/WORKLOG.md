# Work log

Append-only. Add entries only with `scripts/log.sh`, which stamps the time (Asia/Kolkata), the agent and
the current commit. Never edit, delete or reorder an entry. To fix a mistake, append a correction.

Each entry uses these headings:
- **Work:** what was done (and, for a new task, the four lines: outcome, evidence, boundaries, stop condition)
- **Files and decisions:** what changed, and any decision made
- **Validation:** the commands actually run and their actual results
- **Bugs and blockers:**
- **Next:** the exact next action

## 2026-10-18 08:24 IST · Claude Code (Opus 5.5) · HEAD 9c35b01

**Work:** M0 foundations. Outcome: repo with plan, process docs, local CI and hooks, ready for an unattended build. Evidence: `scripts/ci.sh` passes. Boundaries: no feature code, no remote. Stop: first commit made.
**Files and decisions:** CLAUDE.md (template filled in), AGENTS.md, docs/PLAN, STATUS, WORKFLOW, MANIFEST_FORMAT, DECISIONS (DEC-001 to DEC-010), BUGS, WORKLOG; scripts/ci.sh, log.sh, install-hooks.sh, run-app.sh, hooks/pre-commit and pre-push; skeleton Package.swift, KnobsCore, test, App, project.yml. Name "Knobs", MIT license and bundle id io.github.deva0x.Knobs are working choices pending Deva (DEC-010).
**Validation:** `scripts/ci.sh` full: PASS (lint ok, 1 test passed, Debug app build ok). The no-hosted-CI check was tested by creating .github/workflows: ci.sh failed as intended, then passed after it was removed. The pre-commit hook ran `ci.sh fast` on commit 9c35b01: PASS.
**Bugs and blockers:** The standing authorization in CLAUDE.md is PENDING Deva's yes. There's no Developer ID Application certificate and no `knobs-notary` profile yet (only needed for M7).
**Next:** After Deva approves, start M1: the `ToolManifest` model plus decoding of Manifests/ffmpeg.json.

## 2026-10-18 08:45 IST · Claude Code (Opus 5.5) · HEAD d3475f8

**Work:** M1 and M2. Outcome: KnobsCore loads and validates manifests, builds argv plus a colored preview from the same parts, and runs tools with streamed output, progress, cancel and a bounded log. Evidence: `swift test`. Boundaries: no UI. Stop: tests green and committed.
**Files and decisions:** Sources/KnobsCore/Manifest/* (strict JSON reader with exact error paths, validator), Command/* (CommandBuilder, ArgumentSplitter, ShellQuoting, OutputNamer), Running/* (ToolLocator, ToolRunner, ProgressParser, OutputLog); Manifests/ffmpeg.json (6 tasks); MANIFEST_FORMAT gained symbol, tint, progress, {extra} and the .ext path part. Deployment target is now macOS 26 (DEC-012). Standing authorization was recorded (DEC-013). Installed imagemagick, pandoc, exiftool, ocrmypdf, ghostscript, whisper-cpp, rsync and sevenzip, and downloaded ggml-tiny.en.bin into .cache/models.
**Validation:** `swift test`: 83 tests in 11 suites passed. `swift test --filter FFmpegIntegrationTests` ran for real (0.6 s, every ffmpeg task produced its output file). Fast mode skips the integration suite (81 tests). Pre-commit hook passed on e6fd8d2 and d3475f8.
**Bugs and blockers:** none. The first ocrmypdf install hit a Homebrew lock from the parallel install; the retry succeeded.
**Next:** M4 thin app slice with ffmpeg, then screenshots and a design review.
