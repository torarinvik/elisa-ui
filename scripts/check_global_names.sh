#!/usr/bin/env bash
# Elisa's current compiler can resolve same-named module globals through an
# include graph. Keep private mutable state names unique until that behavior is
# fixed upstream; otherwise one backend can silently read another module's
# state while still compiling successfully.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
seen: dict[str, list[str]] = {}
pattern = re.compile(r"^\s*global mutable\s+(\w+)")

for path in sorted((root / "src").rglob("*.elisa")):
    for line_number, line in enumerate(path.read_text().splitlines(), 1):
        match = pattern.match(line)
        if match:
            name = match.group(1)
            seen.setdefault(name, []).append(f"{path.relative_to(root)}:{line_number}")

duplicates = {name: locations for name, locations in seen.items() if len(locations) > 1}
if duplicates:
    for name, locations in sorted(duplicates.items()):
        print(f"global names: duplicate '{name}'", file=sys.stderr)
        for location in locations:
            print(f"  {location}", file=sys.stderr)
    raise SystemExit(1)

print("global names: all mutable module globals are unique")
PY
