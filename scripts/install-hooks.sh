#!/usr/bin/env bash
# Points git at the versioned hooks in scripts/hooks, so hooks update with the repo instead of being copied.
set -euo pipefail
cd "$(dirname "$0")/.."
git config core.hooksPath scripts/hooks
echo "Git hooks enabled from scripts/hooks"
