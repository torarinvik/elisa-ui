#!/usr/bin/env bash
# Resolve and verify the Elisa stage1 product used by elisa-ui builds.
#
# The compiler wrapper has its own stale-source guard, but this separate gate
# makes the selected product auditable before a suite starts and catches a
# dirty compiler checkout that could otherwise make a result irreproducible.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1_INPUT="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"
STAGE1="$(cd -- "$STAGE1_INPUT" && pwd)"
PRODUCT="$STAGE1/bin/elisac-stage1"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"

[[ -x "$PRODUCT" ]] || { echo "toolchain: no stage1 product at $PRODUCT" >&2; exit 2; }
[[ -f "$RUNTIME" ]] || { echo "toolchain: no runtime object at $RUNTIME" >&2; exit 2; }

if git -C "$STAGE1" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    revision="$(git -C "$STAGE1" rev-parse HEAD)"
    branch="$(git -C "$STAGE1" branch --show-current)"
    branch="${branch:-detached}"
    if [[ -n "$(git -C "$STAGE1" status --porcelain --untracked-files=all)" && "${ELISA_ALLOW_DIRTY_STAGE1:-0}" != 1 ]]; then
        echo "toolchain: compiler checkout is dirty: $STAGE1" >&2
        echo "set ELISA_ALLOW_DIRTY_STAGE1=1 only for intentional compiler archaeology" >&2
        exit 2
    fi
    if git -C "$STAGE1" rev-parse --verify origin/main >/dev/null 2>&1; then
        read -r ahead behind <<<"$(git -C "$STAGE1" rev-list --left-right --count HEAD...origin/main)"
        echo "toolchain: stage1 branch=$branch revision=$revision (ahead=$ahead behind=$behind vs origin/main)"
    else
        echo "toolchain: stage1 branch=$branch revision=$revision"
    fi
else
    echo "toolchain: stage1 checkout has no git provenance: $STAGE1" >&2
    if [[ "${ELISA_ALLOW_UNVERIFIED_STAGE1:-0}" != 1 ]]; then
        echo "set ELISA_ALLOW_UNVERIFIED_STAGE1=1 only for an intentional packaged-product check" >&2
        exit 2
    fi
fi

stale_source=""
for source_root in "$STAGE1/src" "$STAGE1/elisacore_std"; do
    [[ -d "$source_root" ]] || continue
    candidate="$(find -H "$source_root" -type f \( -name '*.elisa' -o -name '*.elisai' \) -newer "$PRODUCT" -print -quit)"
    if [[ -n "$candidate" ]]; then
        stale_source="$candidate"
        break
    fi
done
if [[ -n "$stale_source" && "${ELISA_ALLOW_STALE_STAGE1:-0}" != 1 ]]; then
    echo "toolchain: stage1 product is older than compiler source $stale_source" >&2
    echo "rebuild it with $STAGE1/scripts/elisac_stage1.sh --seed" >&2
    exit 2
fi
if [[ -n "$stale_source" ]]; then
    echo "toolchain: WARNING stale product permitted by ELISA_ALLOW_STALE_STAGE1=1" >&2
fi

# The runtime object is built from the std separately from the product, and a seed used
# to leave it behind: the product embedded a std with profiler hooks while the object
# still lacked them, and the pair went a week unnoticed because only the product was
# checked here. Hold the object to the same standard as the product -- newer than every
# std source and than the script that builds it.
stale_runtime=""
for runtime_input in "$STAGE1/elisacore_std" "$STAGE1/scripts/build_runtime_object.sh" "$STAGE1/scripts/write_profiler_hook_fallbacks.sh"; do
    [[ -e "$runtime_input" ]] || continue
    candidate="$(find -H "$runtime_input" -type f -newer "$RUNTIME" -print -quit)"
    if [[ -n "$candidate" ]]; then
        stale_runtime="$candidate"
        break
    fi
done
if [[ -n "$stale_runtime" && "${ELISA_ALLOW_STALE_STAGE1:-0}" != 1 ]]; then
    echo "toolchain: runtime object is older than its input $stale_runtime" >&2
    echo "rebuild it with $STAGE1/scripts/build_runtime_object.sh (a --seed does this too)" >&2
    exit 2
fi
if [[ -n "$stale_runtime" ]]; then
    echo "toolchain: WARNING stale runtime object permitted by ELISA_ALLOW_STALE_STAGE1=1" >&2
fi

echo "toolchain: product=$PRODUCT"
echo "toolchain: product_sha256=$(shasum -a 256 "$PRODUCT" | awk '{print $1}')"
echo "toolchain: runtime=$RUNTIME"
echo "toolchain: runtime_sha256=$(shasum -a 256 "$RUNTIME" | awk '{print $1}')"
