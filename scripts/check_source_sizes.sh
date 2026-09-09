#!/usr/bin/env bash
# Enforce the source-size limits.
#
# Two limits, on purpose. Elisa modules under src/ keep the implementation plan's
# 400-line cohesion limit. Everything else the project writes -- tests, shims, scripts,
# headers, docs -- is held to 600 lines, so no file anywhere needs paging to read; the
# rule that split the AppKit canvas shim, its bridge test, the Skia painter test and the
# baseline document into their current parts. third_party/ is excluded: those files are
# verbatim upstream artifacts (the pinned Unicode conformance corpus among them) whose
# provenance depends on being byte-identical to their source.
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

while IFS= read -r -d '' source; do
  lines="$(wc -l < "$source")"
  if (( lines > 600 )); then
    printf 'source size: %s is %d lines (limit 600)\n' "${source#"$ROOT/"}" "$lines" >&2
    status=1
  fi
done < <(find "$ROOT/src" "$ROOT/test" "$ROOT/scripts" "$ROOT/docs" "$ROOT/include" "$ROOT/examples" \
           -type f \( -name '*.elisa' -o -name '*.m' -o -name '*.c' -o -name '*.cpp' -o -name '*.h' \
                      -o -name '*.sh' -o -name '*.md' -o -name '*.elisascript' -o -name '*.py' \) \
           -not -path "$ROOT/src/*.elisa" -print0)

if (( status != 0 )); then
  exit 1
fi

echo "source sizes: all Elisa modules are within 400 lines; every other source file within 600"
