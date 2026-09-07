#!/usr/bin/env bash
# Enforce the implementation plan's cohesive Elisa-module size limit.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
status=0

while IFS= read -r -d '' source; do
  lines="$(wc -l < "$source")"
  if (( lines > 400 )); then
    printf 'source size: %s is %d lines (limit 400)\n' "${source#"$ROOT/"}" "$lines" >&2
    status=1
  fi
done < <(find "$ROOT/src" -type f -name '*.elisa' -print0)

if (( status != 0 )); then
  exit 1
fi

echo "source sizes: all Elisa modules are within 400 lines"
