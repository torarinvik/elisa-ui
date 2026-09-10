#!/usr/bin/env bash
# The refinement gate: prove that the laws in this repository are ENFORCED.
#
# A refinement type is worth exactly as much as the compiler's willingness to
# complain about it, and both ways of failing are silent. It can stop being
# checked -- a toolchain change, a signature edited back to the bare type -- and
# every call site keeps compiling as if the bound were still there. Or it can
# become impossible to satisfy, and the vocabulary quietly falls out of use
# while the laws sit in the source looking like protection.
#
# So this compiles two fixtures that differ in one thing:
#
#   * unproven_channel.elisa passes an unconstrained integer where a channel is
#     demanded. The compiler MUST say so.
#   * proven_channel.elisa passes the same values through the framework's own
#     `channel` constructor. The compiler must say NOTHING about refinements.
#
# and then holds the whole framework to the second standard: no source in src/
# may leave a refinement obligation of its own undischarged.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"
[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "no stage1 product at $STAGE1/bin/elisac-stage1" >&2; exit 2; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT INT TERM HUP
status=0

# The diagnostic text the compiler uses for an undischarged obligation, on an
# argument and on a return. Matched loosely enough to survive rewording, tightly
# enough that an unrelated warning cannot satisfy the negative case.
REFINEMENT_PATTERN='refinement on (argument|the return)'

compile_fixture() {
  # Compiles one source and echoes the compiler's own diagnostics. A compile
  # that fails outright is reported by the caller: the fixtures are here to
  # produce refinement findings, not build errors.
  local source="$1" object="$2"
  bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$object" "$source" 2>&1 || true
}

negative="$(compile_fixture "$ROOT/test/refinements/unproven_channel.elisa" "$WORK/unproven.o")"
if grep -Eq "$REFINEMENT_PATTERN" <<<"$negative"; then
  echo "refinements: an unproven channel is reported"
else
  echo "FAIL refinements: passing an unconstrained integer where UiChannel is demanded was NOT reported" >&2
  echo "  the law is no longer enforced; every call site that relies on it is unguarded" >&2
  printf '%s\n' "$negative" | sed 's/^/  /' >&2
  status=1
fi

positive="$(compile_fixture "$ROOT/test/refinements/proven_channel.elisa" "$WORK/proven.o")"
if grep -Eq "$REFINEMENT_PATTERN" <<<"$positive"; then
  echo "FAIL refinements: a value carried through UiCore::channel was still reported unproven" >&2
  echo "  the vocabulary cannot be satisfied, which makes it unusable rather than safe" >&2
  printf '%s\n' "$positive" | sed 's/^/  /' >&2
  status=1
elif [[ ! -f "$WORK/proven.o" ]]; then
  echo "FAIL refinements: the positive fixture did not compile" >&2
  printf '%s\n' "$positive" | sed 's/^/  /' >&2
  status=1
else
  echo "refinements: a channel from UiCore::channel is accepted"
fi

# The framework itself. Every law in src/ has to be dischargeable by the code
# that declares it, or it is a bound nobody can honour.
framework="$(compile_fixture "$ROOT/test/color_pack_test.elisa" "$WORK/framework.o")"
if grep -Eq "$REFINEMENT_PATTERN" <<<"$framework"; then
  echo "FAIL refinements: the framework leaves a refinement obligation undischarged" >&2
  printf '%s\n' "$framework" | sed 's/^/  /' >&2
  status=1
else
  echo "refinements: the framework discharges its own laws"
fi

exit "$status"
