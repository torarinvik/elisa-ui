#!/usr/bin/env bash
# Execute the pinned Unicode GraphemeBreakTest corpus through UiText::next_grapheme.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"
LOCK="$ROOT/third_party/unicode.lock"
DATA="${ELISA_UI_UNICODE_DATA:-$ROOT/third_party/unicode/GraphemeBreakTest-15.1.0.txt}"

[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "unicode: no stage1 product at $STAGE1/bin/elisac-stage1" >&2; exit 2; }
[[ -f "$RUNTIME" ]] || { echo "unicode: no runtime object at $RUNTIME" >&2; exit 2; }
[[ -f "$LOCK" ]] || { echo "unicode: missing lock at $LOCK" >&2; exit 2; }

WORK="$(mktemp -d "$ROOT/build/unicode-conformance.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

if [[ ! -f "$DATA" ]]; then
  url="$(awk -F= '/^grapheme_break_test_url[[:space:]]*=/{gsub(/[[:space:]]/, "", $2); print $2}' "$LOCK")"
  [[ -n "$url" ]] || { echo "unicode: lock has no GraphemeBreakTest URL" >&2; exit 2; }
  command -v curl >/dev/null 2>&1 || { echo "unicode: curl is required to fetch pinned Unicode data" >&2; exit 2; }
  DATA="$WORK/GraphemeBreakTest-15.1.0.txt"
  curl -L --fail --silent --show-error "$url" -o "$DATA"
fi

expected="$(awk -F= '/^grapheme_break_test_sha256[[:space:]]*=/{gsub(/[[:space:]]/, "", $2); print $2}' "$LOCK")"
actual="$(shasum -a 256 "$DATA" | awk '{print $1}')"
[[ "$actual" == "$expected" ]] || {
  echo "unicode: GraphemeBreakTest hash mismatch (expected $expected, got $actual)" >&2
  exit 2
}

python3 - "$DATA" "$WORK/full.elisa" <<'PY'
from pathlib import Path
import sys

data_path = Path(sys.argv[1])
source_path = Path(sys.argv[2])
rows = []
for line in data_path.read_text(encoding="utf-8").splitlines():
    payload = line.split("#", 1)[0].strip()
    if not payload:
        continue
    tokens = payload.split()
    codepoints = []
    breaks = []
    pending_break = False
    for token in tokens:
        if token == "÷":
            pending_break = True
        elif token == "×":
            pending_break = False
        else:
            codepoints.append(int(token, 16))
            breaks.append(pending_break)
            pending_break = False
    breaks.append(True)
    rows.append((codepoints, breaks))

def encoded(codepoint):
    return chr(codepoint).encode("utf-8")

out = [
    'include "../../src/core/ui_core.elisa"',
    'global mutable failures: i32 = 0',
]
for index, (codepoints, breaks) in enumerate(rows):
    encoded_text = b"".join(encoded(codepoint) for codepoint in codepoints)
    boundaries = []
    offset = 0
    for item, codepoint in enumerate(codepoints):
        offset += len(encoded(codepoint))
        if item + 1 < len(codepoints) and breaks[item + 1]:
            boundaries.append(offset)
    boundaries.append(len(encoded_text))
    out.extend([
        f"def unicode_case_{index}() -> bool:",
        f"    bytes: mutable u8[{max(1, len(encoded_text))}] = zeroed",
    ])
    out.extend(f"    bytes[{position}] <- {value}" for position, value in enumerate(encoded_text))
    out.extend([
        f"    text: sview = sview(&bytes[0], 0, {len(encoded_text)})",
        "    position: mutable usize = 0",
        "    next: mutable usize = 0",
    ])
    for boundary in boundaries:
        out.extend([
            "    next <- UiText::next_grapheme(text, position)",
            f"    return false if next != {boundary} or next <= position",
            "    position <- next",
        ])
    out.extend([f"    return position == {len(encoded_text)}", ""])

out.extend([
    "def unicode_full_conformance() -> i32:",
    "    failures <- 0",
])
out.extend(f"    failures <- failures + 1 if not unicode_case_{index}()" for index in range(len(rows)))
out.extend([
    "    return failures",
    "",
    "export fn elisa_unicode_full_conformance() -> i32 = unicode_full_conformance",
])
source_path.write_text("\n".join(out) + "\n", encoding="utf-8")
PY

# The generator's stdout is intentionally not part of the result contract;
# count the corpus from its source so a truncated generation cannot pass.
row_count="$(rg -c '^def unicode_case_' "$WORK/full.elisa")"
[[ "$row_count" -gt 0 ]] || { echo "unicode: generated corpus is empty" >&2; exit 2; }

bash "$STAGE1/scripts/elisac_stage1.sh" -O2 -o "$WORK/full.o" "$WORK/full.elisa"
clang -x c -std=c11 -Wall -Wextra -Werror -c -o "$WORK/runner.o" - <<'EOF'
#include <stdint.h>
#include <stdio.h>
extern int32_t elisa_unicode_full_conformance(void);
int main(void) {
    const int32_t failures = elisa_unicode_full_conformance();
    if (failures != 0) {
        fprintf(stderr, "unicode: %d of the pinned rows failed\n", failures);
        return 1;
    }
    return 0;
}
EOF
clang -Wl,-dead_strip -o "$WORK/unicode" "$WORK/runner.o" "$WORK/full.o" "$RUNTIME"
"$WORK/unicode"
echo "unicode UAX #29 15.1.0: $row_count rows passed (data sha256=$actual)"
