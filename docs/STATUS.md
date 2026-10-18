# Status

Editable snapshot of where things stand. The history lives in `docs/WORKLOG.md`.

Updated: 2026-10-18 IST

## Now
- Milestone: M0 (foundations).
- Done: repo, template guardrails, plan and process docs, local CI and hooks, app and core skeleton.
- Next action: once Deva approves, run one `brew install exiftool` and download the whisper test model (DEC-009) first, so any permission prompt shows up while Deva can still answer it. Then start M1: the `ToolManifest` model and decoding the ffmpeg manifest.

## Waiting on Deva
1. Approve the plan and the standing authorization in CLAUDE.md (local commits, Homebrew installs, the
   whisper test model).
2. Create the Developer ID Application certificate (see WORKFLOW, "Releasing"). Needed only for M7.
3. Store the notary profile `knobs-notary` (see WORKFLOW). Needed only for M7.
4. Decide the final name and license before publishing (M8).

## Blocked
Nothing.
