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
  "tasks": [
    {
      "id": "shrink-video",
      "title": "Shrink a video",
      "summary": "Make a video file smaller, for sharing or email.",
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
| `id` | string | yes | Unique, lowercase, `a-z0-9-` |
| `name` | string | yes | Shown in the sidebar |
| `summary` | string | yes | One sentence, plain words |
| `executable` | string | yes | Binary name looked up by `ToolLocator`. A name only, never a path |
| `install.brew` | string | yes | Homebrew formula, shown as `brew install <formula>` |
| `homepage` | string | no | Link shown in the tool's header |
| `tasks` | array | yes | At least one task |

## Task

| Key | Type | Required | Meaning |
|---|---|---|---|
| `id` | string | yes | Unique within the manifest |
| `title` | string | yes | Verb first, sentence case: "Shrink a video" |
| `summary` | string | yes | One sentence |
| `fields` | array | yes | The controls, in display order |
| `output` | object | no | How to name the output file, see below |
| `arguments` | array | yes | The argv template, see below |

## Fields

Every field has `id`, `label` and `kind`. `help` (one sentence under the control) is optional, and so is
`required` (default `true` for files and folders, `false` otherwise).

| `kind` | Control | Value | Extra keys |
|---|---|---|---|
| `inputFile` | File picker and drop target | absolute path | `contentTypes`: UTType identifiers. `multiple`: boolean |
| `inputFolder` | Folder picker | absolute path | none |
| `outputFolder` | Folder picker | absolute path | none |
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
  `"else": [ ... ]` is optional. Conditionals can nest.
- **`{output}`** is the derived output path from `output`.

Placeholders that can be used:
- `{fieldId}` is the field's value.
- `{fieldId.stem}` is a file name without its folder or extension.
- `{fieldId.name}` is a file name without its folder.
- `{fieldId.dir}` is a file's folder.

A string that consists only of a placeholder for an empty, optional value produces no argument.
Validation rejects a reference to a field that doesn't exist.

## Output

`output.template` uses the same placeholders. `output.nextTo` names the file field whose folder receives the
output, or `output.folder` names an `outputFolder` field. If the file already exists, Knobs adds " 2",
" 3" and so on before the extension. It never overwrites a file.

## Validation errors

Loading a manifest fails with a message naming the file, the JSON path and the problem when any of these
happen:
- an unknown `kind`, or an unknown key in a field or task
- a duplicate tool, task or field id
- a placeholder or `if` that refers to a field that doesn't exist
- a `default` outside `minimum`/`maximum`, or not one of the `options`
- `executable` containing `/`
- `schemaVersion` other than 1

## Versioning

A change that would break existing manifests requires `schemaVersion: 2`. Knobs keeps loading version 1.
