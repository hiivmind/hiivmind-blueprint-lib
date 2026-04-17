#!/usr/bin/env bash
#
# migrate-v7-to-v8.sh — Convert a v7 workflow.yaml's endings: block into nodes: entries.
#
# Usage: scripts/migrate-v7-to-v8.sh <workflow.yaml> [<workflow.yaml> ...]
#
# In-place edit. Requires yq v4+.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <workflow.yaml> [<workflow.yaml> ...]" >&2
  exit 2
fi

command -v yq >/dev/null 2>&1 || { echo "yq not found" >&2; exit 3; }

for file in "$@"; do
  if [[ ! -f "$file" ]]; then
    echo "skip: $file (not found)" >&2
    continue
  fi

  # Only run if there is a top-level endings: block.
  if ! yq -e '.endings' "$file" >/dev/null 2>&1; then
    echo "skip: $file (no endings: block)" >&2
    continue
  fi

  # For each endings.<id>, copy to nodes.<id> with type: ending and
  # rename the original .type field (success/failure/…) to .outcome.
  yq -i '
    (.endings[]) |= (. + {"outcome": .type})
    | (.endings[].type) = "ending"
    | .nodes = (.nodes // {}) * .endings
    | del(.endings)
  ' "$file"

  echo "migrated: $file"
done
