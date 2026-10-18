# Contributing to Knobs

Thanks for helping. Most contributions are one of three things: a new task for a tool Knobs already has, a
manifest for a new tool, or a fix. None of the first two needs any Swift.

## Before you start

You need macOS 26 or later on Apple Silicon, Xcode 26 or later, and XcodeGen (`brew install xcodegen`).

```bash
scripts/install-hooks.sh   # once per clone: runs the checks before every commit and push
scripts/ci.sh              # lint, unit tests, integration tests and an app build
scripts/run-app.sh         # build and open the app
```

All checks run on your own Mac. Knobs has no hosted CI, and pull requests must not add any: `scripts/ci.sh`
fails if `.github/workflows` exists.

## Adding a task or a tool

Every tool is one JSON file in [Manifests/](Manifests/). The full format is in
[docs/MANIFEST_FORMAT.md](docs/MANIFEST_FORMAT.md). This is the short version.

1. **Copy a similar manifest.** `Manifests/rsync.json` is a good small example; `Manifests/ffmpeg.json` shows
   most features. Give the tool a lowercase `id`, its bare `executable` name (never a path), the Homebrew
   formula under `install`, an SF Symbol and a tint.
2. **Write tasks people actually ask for,** in plain words: "Shrink a video", not "Transcode with libx264".
   Three to six tasks is right. Anything rarer is still reachable through Extra arguments and All options.
3. **Describe the fields,** such as files, folders, choices, numbers, on/off switches and text. Labels are
   short and plain. Give everything a sensible default so most people only drop a file and press Run.
4. **Write the arguments as a list.** Each item becomes exactly one argument; `{field}` puts a value in,
   `{extra}` marks where Extra arguments go (exactly once), and `{ "if": ..., "then": [...] }` adds arguments
   only when a switch is on or a choice matches. Knobs never uses a shell, so there is no quoting to get right.
5. **Name the output** with an `output` rule, so Knobs can show the result and never overwrite a file.
6. **Add progress** if the tool prints a percentage or a time, so the window can show a progress bar.
7. **Test it:**
   - `swift test --filter ManifestLoadingTests` checks that every manifest in the folder loads and validates.
   - Add a golden test in `Tests/KnobsCoreTests/CommandBuilderTests.swift` if the task has conditionals.
   - Add your tool to `Tests/KnobsCoreTests/Integration/ToolIntegrationTests.swift` so every task really runs
     on a tiny file. Tests skip when the tool isn't installed, unless `KNOBS_REQUIRE_TOOLS=1` is set.
   - Run the task once in the app and check the result.

If the format can't express something your tool needs, open an issue first. Tool-specific behavior belongs in
the manifest, so the fix is usually a small, general addition to the format and to `KnobsCore` together.

## Code changes

- Read [CLAUDE.md](CLAUDE.md) (the repo's working rules, for people and agents alike) and
  [docs/WORKFLOW.md](docs/WORKFLOW.md).
- Tools always run through `Process` with an argument list, never through `/bin/sh -c` or a command string.
- UI changes follow [docs/DESIGN.md](docs/DESIGN.md) and its review checklist. Include light and dark
  screenshots in the pull request.
- Keep one concern per commit, and write the message as `area: why`, for example
  `manifests: add a Trim task to ffmpeg`.
- Format with `xcrun swift-format format --in-place --recursive Sources Tests App`.

## Reporting bugs

Say what you did, what you expected and what happened, and include the command Knobs showed (the Copy
button in the command bar copies it). Leave out personal file paths if you'd rather not share them.
