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
