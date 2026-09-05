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
#include <string.h>
#include "elisa_ui.h"

static elisa_ui_event seen;
static int events;
static int text_events;

void elisa_ui_on_init(void) {}
void elisa_ui_on_frame(void) {}
void elisa_ui_on_widget_event(size_t widget, int32_t event) { (void)widget; (void)event; }
void elisa_ui_on_event(const elisa_ui_event *event) { seen = *event; events++; }
void elisa_ui_on_text_input(const char *text, size_t length) {
    if (length == strlen("Hé 👋") && memcmp(text, "Hé 👋", length) == 0) text_events++;
}
void elisa_ui_on_text_editing(const char *text, size_t length, int32_t selected_start, int32_t selected_length) {
    (void)text; (void)length; (void)selected_start; (void)selected_length;
}

int main(void) {
    int failures = 0;

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
    elisa_ui_dispatch_text_input(NULL, 4);
    if (text_events != 1) { puts("null text pointer was not ignored"); failures++; }
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
clang -Wl,-dead_strip -o "$WORK/capi_host" "$WORK/host.o" "$WORK/bridge.o" "$RUNTIME"
rm -f "$ROOT/build/capi_bridge_link.elisa"
"$WORK/capi_host"
