#!/usr/bin/env bash
# Build a real C program against the library and run it.
#
# The header and the Elisa side are two hand-written descriptions of one ABI, and
# nothing else checks that they agree: the elisa suite never sees the header, and
# the header never sees the Elisa types. This links them and asserts a struct
# whose layout C computed reaches an Elisa function with its fields intact.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"
[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "no stage1 product at $STAGE1/bin/elisac-stage1" >&2; exit 2; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT INT TERM HUP
mkdir -p "$ROOT/build"

# The Elisa side: both adapters at once, which also proves they can coexist.
cat > "$WORK/bridge.elisa" <<'EOF'
include "../src/capi/ui_capi.elisa"
include "../src/capi/ui_capi_app.elisa"
EOF
# `include` is resolved relative to the including file, so build it in place.
cp "$WORK/bridge.elisa" "$ROOT/build/capi_bridge_link.elisa"
bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$WORK/bridge.o" "$ROOT/build/capi_bridge_link.elisa"

cat > "$WORK/host.c" <<'EOF'
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#include "elisa_ui.h"

_Static_assert(sizeof(elisa_ui_event) == 24, "event record size changed");
_Static_assert(offsetof(elisa_ui_event, kind) == 0, "event kind offset changed");
_Static_assert(offsetof(elisa_ui_event, x) == 4, "event x offset changed");
_Static_assert(offsetof(elisa_ui_event, y) == 8, "event y offset changed");
_Static_assert(offsetof(elisa_ui_event, dx) == 12, "event dx offset changed");
_Static_assert(offsetof(elisa_ui_event, dy) == 16, "event dy offset changed");
_Static_assert(offsetof(elisa_ui_event, code) == 20, "event code offset changed");
_Static_assert(ELISA_UI_EVENT_FOCUS_LOST == 13, "event ordinals changed");

static elisa_ui_event seen;
static int events;
static int text_events;
static size_t last_text_length;
static int editing_events;
static int32_t editing_start;
static int32_t editing_length;

void elisa_ui_on_init(void) {}
void elisa_ui_on_frame(void) {}
void elisa_ui_on_widget_event(size_t widget, int32_t event) { (void)widget; (void)event; }
void elisa_ui_on_event(const elisa_ui_event *event) { seen = *event; events++; }
void elisa_ui_on_text_input(const char *text, size_t length) {
    last_text_length = length;
    if (length == strlen("Hé 👋") && memcmp(text, "Hé 👋", length) == 0) text_events++;
}
void elisa_ui_on_text_editing(const char *text, size_t length, int32_t selected_start, int32_t selected_length) {
    if (length == strlen("é 👋") && memcmp(text, "é 👋", length) == 0) editing_events++;
    editing_start = selected_start;
    editing_length = selected_length;
}

int main(void) {
    int failures = 0;

    if (elisa_ui_abi_version() != ELISA_UI_ABI_VERSION) {
        puts("C ABI version did not match the header"); failures++;
    }

    /* C host -> Elisa -> back out to the C app callback, through the hierarchy
     * both ways. A pointer-down must keep its position and its button. */
    elisa_ui_dispatch_event(ELISA_UI_EVENT_POINTER_DOWN, 12.5f, 34.25f, 0.0f, 0.0f, 2);
    if (events != 1)                            { puts("no event reached the C app"); failures++; }
    if (seen.kind != ELISA_UI_EVENT_POINTER_DOWN) { puts("kind did not survive"); failures++; }
    if (seen.x != 12.5f || seen.y != 34.25f)    { puts("position did not survive"); failures++; }
    if (seen.code != 2)                         { puts("button did not survive"); failures++; }

    elisa_ui_dispatch_event(ELISA_UI_EVENT_SCROLL, 1.0f, 2.0f, 3.0f, -4.0f, 0);
    if (seen.dx != 3.0f || seen.dy != -4.0f)    { puts("scroll delta did not survive"); failures++; }

    /* GLFW's Escape, which is what UiCore::Key names. */
    elisa_ui_dispatch_event(ELISA_UI_EVENT_KEY_UP, 0.0f, 0.0f, 0.0f, 0.0f, 256);
    if (seen.kind != ELISA_UI_EVENT_KEY_UP || seen.code != 256) { puts("key did not survive"); failures++; }

    elisa_ui_dispatch_text_input("Hé 👋", strlen("Hé 👋"));
    if (text_events != 1) { puts("UTF-8 text did not survive"); failures++; }
    elisa_ui_dispatch_text_editing("é 👋", strlen("é 👋"), 99, 99);
    if (editing_events != 1 || editing_start != 3 || editing_length != 0) {
        puts("UTF-8 IME composition did not survive"); failures++;
    }
    elisa_ui_dispatch_text_editing(NULL, 0, 4, 4);
    if (editing_start != 0 || editing_length != 0) {
        puts("empty IME composition was not bounded"); failures++;
    }
    elisa_ui_dispatch_text_input(NULL, 4);
    if (text_events != 1) { puts("null text pointer was not ignored"); failures++; }
    char oversized_text[1032];
    memset(oversized_text, 'x', sizeof(oversized_text));
    elisa_ui_dispatch_text_input(oversized_text, sizeof(oversized_text));
    if (last_text_length != 1024) { puts("oversized text was not bounded"); failures++; }
    elisa_ui_dispatch_text_input("x", SIZE_MAX);
    if (text_events != 1) { puts("oversized text length was not ignored"); failures++; }

    /* An ordinal the library does not model is NONE, not a trap. */
    elisa_ui_dispatch_event(99, 0.0f, 0.0f, 0.0f, 0.0f, 0);
    if (seen.kind != ELISA_UI_EVENT_NONE)       { puts("an unknown ordinal was not NONE"); failures++; }

    elisa_ui_set_viewport(800.0f, 600.0f);
    if (elisa_ui_viewport_width() != 800.0f || elisa_ui_viewport_height() != 600.0f) {
        puts("viewport did not survive"); failures++;
    }
    elisa_ui_set_viewport(-10.0f, -20.0f);
    if (elisa_ui_viewport_width() != 0.0f || elisa_ui_viewport_height() != 0.0f) {
        puts("negative viewport was not normalized"); failures++;
    }

    if (failures == 0) { puts("capi: all checks passed"); return 0; }
    puts("capi: FAILURES above");
    return 1;
}
EOF

clang -std=c11 -Wall -Wextra -I"$ROOT/include" -c -o "$WORK/host.o" "$WORK/host.c"
cat > "$WORK/header_cpp.cc" <<'EOF'
#include <cstddef>
#include "elisa_ui.h"

static_assert(sizeof(elisa_ui_event) == 24, "event record size changed");
static_assert(offsetof(elisa_ui_event, code) == 20, "event code offset changed");
static_assert(ELISA_UI_EVENT_FOCUS_LOST == 13, "event ordinals changed");

int main() { return ELISA_UI_ABI_VERSION == 0x000100u ? 0 : 1; }
EOF
clang++ -std=c++17 -Wall -Wextra -Werror -I"$ROOT/include" \
  -c -o "$WORK/header_cpp.o" "$WORK/header_cpp.cc"
clang -Wl,-dead_strip -o "$WORK/capi_host" "$WORK/host.o" "$WORK/bridge.o" "$RUNTIME"
rm -f "$ROOT/build/capi_bridge_link.elisa"
"$WORK/capi_host"
