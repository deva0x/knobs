#!/usr/bin/env bash
# Appends one entry to docs/WORKLOG.md. It only ever appends; existing entries are never touched.
# Usage: scripts/log.sh "<agent name>" <<'ENTRY'
#   ...body using the headings shown at the top of docs/WORKLOG.md...
# ENTRY
set -euo pipefail

agent="${1:?usage: scripts/log.sh <agent name>  (entry body on stdin)}"
worklog="$(cd "$(dirname "$0")/.." && pwd)/docs/WORKLOG.md"
body="$(cat)"
if [ -z "${body//[[:space:]]/}" ]; then
    echo "log.sh: empty entry, nothing written" >&2
    exit 1
fi

stamp="$(TZ=Asia/Kolkata date '+%Y-%m-%d %H:%M IST')"
head_commit="$(git -C "$(dirname "$worklog")" rev-parse --short HEAD 2>/dev/null || echo 'no commits')"
printf '\n## %s · %s · HEAD %s\n\n%s\n' "$stamp" "$agent" "$head_commit" "$body" >>"$worklog"
echo "log.sh: appended entry at $stamp"
