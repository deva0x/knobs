# Manifest format, version 1

A manifest is one JSON file in `Manifests/` that describes one command-line tool and the everyday tasks
Knobs offers for it. The app builds its windows from manifests and contains no tool-specific code.
Adding a tool means adding a manifest, not writing Swift.

This document is the specification. `KnobsCore` implements it, and its tests use the manifests in
`Manifests/` as examples. If the code and this document disagree, fix one of them in the same commit.

## Example

```json
{
  "schemaVersion": 1,
  "id": "ffmpeg",
  "name": "ffmpeg",
  "summary": "Convert, shrink and trim video and audio.",
  "executable": "ffmpeg",
  "install": { "brew": "ffmpeg" },
  "homepage": "https://ffmpeg.org",
  "symbol": "film.stack",
  "tint": "purple",
  "tasks": [
    {
      "id": "shrink-video",
      "title": "Shrink a video",
      "summary": "Make a video file smaller, for sharing or email.",
      "symbol": "arrow.down.right.and.arrow.up.left",
      "fields": [
        { "id": "input", "label": "Video", "kind": "inputFile", "contentTypes": ["public.movie"] },
        { "id": "size", "label": "Size", "kind": "choice", "default": "1280",
          "options": [
            { "value": "1280", "label": "720p" },
            { "value": "1920", "label": "1080p" },
            { "value": "", "label": "Keep original" }
          ] },
        { "id": "quality", "label": "Quality", "kind": "integer", "default": 23, "minimum": 18, "maximum": 32,
          "help": "Lower is better quality and a bigger file." },
        { "id": "mute", "label": "Remove sound", "kind": "toggle", "default": false }
      ],
      "output": { "template": "{input.stem} small.mp4", "nextTo": "input" },
      "arguments": [
        "-hide_banner", "-i", "{input}",
        { "if": "size", "then": ["-vf", "scale={size}:-2"] },
        "-crf", "{quality}",
        { "if": "mute", "then": ["-an"] },
        "{extra}",
        "{output}"
      ]
    }
  ]
}
```

## Top level

| Key | Type | Required | Meaning |
|---|---|---|---|
| `schemaVersion` | integer | yes | Always `1` for this version |
| `id` | string | yes | Unique, lowercase letters, digits and single dashes |
| `name` | string | yes | Shown in the sidebar |
| `summary` | string | yes | One sentence, plain words |
| `executable` | string | yes | Binary name looked up by `ToolLocator`. A name only, never a path |
| `install.brew` | string | yes | Homebrew formula, shown as `brew install <formula>` |
| `homepage` | string | no | Link shown in the tool's header |
| `symbol` | string | yes | SF Symbol name for the tool's glyph tile |
| `tint` | string | yes | One of `purple`, `red`, `teal`, `indigo`, `orange`, `blue`, `gray`, `green`, `cyan`, `brown`, `pink`, `yellow`, `mint` |
| `tasks` | array | yes | At least one task |
| `helpArguments` | array of strings | no | What makes the tool print its options, for the "All options" view. Default `["--help"]`; ffmpeg uses `["-hide_banner", "-h", "long"]` |

## Task

| Key | Type | Required | Meaning |
|---|---|---|---|
| `id` | string | yes | Unique within the manifest |
| `title` | string | yes | Verb first, sentence case: "Shrink a video" |
| `summary` | string | yes | One sentence |
| `symbol` | string | yes | SF Symbol name for the task card |
| `fields` | array | yes | The controls, in display order |
| `output` | object | no | How to name the output file, see below |
| `arguments` | array | yes | The argv template, see below |
| `progress` | object | no | How to read progress from the tool's output, see below |
| `outputPathPattern` | string | no | A regular expression with one group that captures the output file's path from the tool's own output, for tools that name their files themselves (yt-dlp, whisper.cpp). The app uses it for the result card. |

## Fields

Every field has `id`, `label` and `kind`. A field `id` starts with a letter and uses only letters and digits (`input`, `startTime`); `extra` and `output` are reserved. `help` (one sentence under the control) is optional, and so is
`required` (default `true` for files and folders, `false` otherwise).

| `kind` | Control | Value | Extra keys |
|---|---|---|---|
| `inputFile` | File picker and drop target | absolute path | `contentTypes`: UTType identifiers. `multiple`: boolean |
| `inputFolder` | Folder picker | absolute path | `default`: a path; `~/` means the home folder |
| `outputFolder` | Folder picker | absolute path | `default`: a path such as `~/Downloads` |
| `choice` | Pop-up menu | one option's `value` | `options` (required), `default` |
| `integer` | Stepper and slider | whole number | `minimum`, `maximum` (both required), `default` |
| `number` | Text field | decimal number | `minimum`, `maximum`, `default` |
| `toggle` | Checkbox | true or false | `default` |
| `text` | Text field | string | `placeholder`, `default` |
| `secret` | Secure text field | string, never saved in presets or shown in the preview | none |

An `inputFile` field with `multiple: true` expands to one argument per file, in the order the user added them.

## Arguments template

`arguments` is a list. Each item is one of the following:

- **A string.** It becomes exactly one argument. `{fieldId}` inside it is replaced by that field's value,
  so `"scale={size}:-2"` becomes `scale=1280:-2`. A value is never split on spaces and never passed through
  a shell, so a file named `my video; rm -rf ~.mov` is just a file name.
- **A conditional object:** `{ "if": "fieldId", "then": [ ... ] }` includes the nested items only when the
  field is set. A toggle is set when it's true. Any other kind is set when its value isn't empty.
  With `"equals": "value"` the condition holds only when the field's value is exactly that text, which suits
  choices (`{ "if": "mode", "equals": "pad", "then": [...] }`); for a choice, the value must be one of its
  options. `"else": [ ... ]` is optional. Conditionals can nest.
- **`{output}`** is the derived output path from `output`.
- **`{extra}`** marks where the task's "Extra arguments" box goes. Every task must contain it exactly once,
  as a whole string. Knobs splits the box's text into words itself, following shell quote rules
  (`"two words"` and `'two words'` stay one argument, and a backslash escapes the next character), and inserts
  those words at this position. Nothing is ever passed to a shell. When the box is empty, it adds nothing.

Placeholders that can be used:
- `{fieldId}` is the field's value.
- `{fieldId.stem}` is a file name without its folder or extension.
- `{fieldId.name}` is a file name without its folder.
- `{fieldId.ext}` is a file's extension without the dot (`mov`).
- `{fieldId.dir}` is a file's folder.
- `{fieldId.base}` is the whole path without its extension (`/a/clip`).
- `{output}` takes the same parts: `{output.base}`, `{output.dir}` and so on, for tools that want an output
  name without its extension.

For a field that holds several files, a part placeholder used inside the output template stands for the first
file.

A string that consists only of a placeholder for an empty, optional value produces no argument.
Validation rejects a reference to a field that doesn't exist.

## Output

`output.template` uses the same placeholders. `output.nextTo` names the file field whose folder receives the
output (the first file's folder, for a field with several files), or `output.folder` names an `outputFolder`
field. If the file already exists, Knobs adds " 2",
" 3" and so on before the extension. It never overwrites a file.

## Progress

Optional. Knobs reads the tool's output line by line (stdout and stderr) and applies these patterns. The
patterns are regular expressions, and each capture group must hold a number.
- `{ "percent": "(\\d+(?:\\.\\d+)?)%" }` reads a percentage directly (yt-dlp, 7-Zip).
- `{ "total": "Duration: (\\d+):(\\d+):(\\d+(?:\\.\\d+)?)", "current": "time=(\\d+):(\\d+):(\\d+(?:\\.\\d+)?)" }`
  reads a current and a total time as hours, minutes and seconds, and progress is current ÷ total (ffmpeg).
  Either pattern may also have a single group holding plain seconds.
Without `progress`, the app shows an indeterminate progress bar.

## Validation errors

Loading a manifest fails with a message naming the file, the JSON path and the problem when any of these
happen:
- an unknown `kind`, or an unknown key in a field or task
- a duplicate tool, task or field id
- a placeholder or `if` that refers to a field that doesn't exist
- a `default` outside `minimum`/`maximum`, or not one of the `options`
- `executable` containing `/`
- `schemaVersion` other than 1
- a task without exactly one `{extra}`, or a field whose id is `extra` or `output` (both are reserved)
- an `equals` that isn't one of a choice's option values
- an `outputPathPattern` that doesn't compile or doesn't have exactly one capture group

## Versioning

A change that would break existing manifests requires `schemaVersion: 2`. Knobs keeps loading version 1.
