# Security

## Reporting a problem

Please report security problems privately, through GitHub's "Report a vulnerability" button on the
repository's Security tab, rather than in a public issue. Include the steps to reproduce it and the command
Knobs showed. You'll get a reply within a week.

## How Knobs keeps you safe

- **No shell, ever.** Tools run through `Process` with an argument list. A file name such as
  `$(rm -rf ~).mov` is just a file name: it reaches the tool as one argument and nothing interprets it.
  Extra arguments are split into words by Knobs itself, following shell quoting rules, and are never passed
  to a shell either.
- **Nothing is overwritten.** Output names that already exist get " 2", " 3" and so on. A task that writes
  several files, such as every page of a PDF, gets a new folder that Knobs makes for it first.
- **What you see is what runs.** The command bar is built from the same argument list that runs.
- **Help text and manifests are data.** "All options" turns a tool's help text into labels and arguments
  only; nothing in it is executed. Manifests are validated strictly, and only web addresses are opened as
  homepages.
- **Passwords aren't stored.** Secret fields are masked in the command, never saved with remembered
  settings or presets, and can't be part of an output file name.
- **Quitting stops tools.** Knobs asks before quitting during a run, then stops the tool and any helpers it
  started.
- **Updates are signed, and checking asks first (Mac).** Knobs never goes online on its own until you say so: on
  its second launch it asks whether to check for updates automatically. A check is one request to
  `knobs.pages.dev/appcast.xml`; it sends nothing about you or your Mac beyond the User-Agent
  "Knobs/<version> Sparkle/<version>". An update downloads from the GitHub release and is installed only if its
  EdDSA signature matches the key built into Knobs, checked before the download is opened. Turn automatic checks
  on or off any time with Knobs > Check for Updates Automatically.

## Known limits

- **Arguments are visible to your other processes.** Like any program started with arguments, a password
  passed to a tool (for example 7-Zip's `-p`) can be seen by other programs running as you, through tools
  such as `ps`, while that tool runs. This is how the tools themselves take passwords.
- **Knobs isn't sandboxed.** It runs tools installed on your Mac with your permissions, so it can't be in the
  Mac App Store (DEC-003). Only install tools you trust.
- **Two runs at the same moment.** The output name is chosen when you press Run. Two runs started at the
  same moment on the same file could pick the same name; some tools then fail and others overwrite.
