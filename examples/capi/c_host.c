/* Minimal C host/app example for elisa-ui's stable boundary.
 *
 * The application callbacks are ordinary C functions. The framework owns the
 * event hierarchy and invokes these callbacks after the host sends typed wire
 * records through elisa_ui_dispatch_*.
 */
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#include "elisa_ui.h"

_Static_assert(sizeof(elisa_ui_event) == 24, "event record size changed");
_Static_assert(offsetof(elisa_ui_event, code) == 20, "event code offset changed");
_Static_assert(ELISA_UI_EVENT_FOCUS_LOST == 13, "event ordinals changed");

static elisa_ui_event last_event;
static size_t last_text_length;
static int event_count;
static int text_count;
static int editing_count;
static int32_t editing_start;
static int32_t editing_length;

void elisa_ui_on_init(void) {}
void elisa_ui_on_frame(void) {}
void elisa_ui_on_widget_event(elisa_ui_widget_handle widget, int32_t event) {
    (void)widget;
    (void)event;
}

void elisa_ui_on_event(const elisa_ui_event *event) {
    last_event = *event;
    event_count++;
}

void elisa_ui_on_text_input(const char *text, size_t length) {
    last_text_length = length;
    if (length == strlen("Hé 👋") && memcmp(text, "Hé 👋", length) == 0) {
        text_count++;
    }
}

void elisa_ui_on_text_editing(const char *text, size_t length,
                              int32_t selected_start, int32_t selected_length) {
    if (length == strlen("é 👋") && memcmp(text, "é 👋", length) == 0) {
        editing_count++;
    }
    editing_start = selected_start;
    editing_length = selected_length;
}

int main(void) {
    int failures = 0;

    if (elisa_ui_abi_version() != ELISA_UI_ABI_VERSION) {
        puts("C ABI version did not match the header");
        failures++;
    }

    elisa_ui_dispatch_event(ELISA_UI_EVENT_POINTER_DOWN,
                            12.5f, 34.25f, 0.0f, 0.0f, 2);
    if (event_count != 1 || last_event.kind != ELISA_UI_EVENT_POINTER_DOWN ||
        last_event.x != 12.5f || last_event.y != 34.25f || last_event.code != 2) {
        puts("pointer event did not survive");
        failures++;
    }

    elisa_ui_dispatch_event(ELISA_UI_EVENT_SCROLL,
                            1.0f, 2.0f, 3.0f, -4.0f, 0);
    if (last_event.dx != 3.0f || last_event.dy != -4.0f) {
        puts("scroll delta did not survive");
        failures++;
    }

    elisa_ui_dispatch_text_input("Hé 👋", strlen("Hé 👋"));
    if (text_count != 1) {
        puts("UTF-8 text did not survive");
        failures++;
    }

    elisa_ui_dispatch_text_editing("é 👋", strlen("é 👋"), 99, 99);
    if (editing_count != 1 || editing_start != 3 || editing_length != 0) {
        puts("UTF-8 IME composition did not survive");
        failures++;
    }

    /* Null/oversized inputs fail closed or clip to the documented budget. */
    elisa_ui_dispatch_text_editing(NULL, 0, 4, 4);
    if (editing_start != 0 || editing_length != 0) {
        puts("empty IME composition was not bounded");
        failures++;
    }
    elisa_ui_dispatch_text_input(NULL, 4);
    char oversized_text[1032];
    memset(oversized_text, 'x', sizeof(oversized_text));
    elisa_ui_dispatch_text_input(oversized_text, sizeof(oversized_text));
    if (last_text_length != 1024) {
        puts("oversized text was not bounded");
        failures++;
    }
    elisa_ui_dispatch_text_input("x", SIZE_MAX);

    elisa_ui_set_viewport(800.0f, 600.0f);
    if (elisa_ui_viewport_width() != 800.0f ||
        elisa_ui_viewport_height() != 600.0f) {
        puts("viewport did not survive");
        failures++;
    }
    elisa_ui_set_viewport(-10.0f, -20.0f);
    if (elisa_ui_viewport_width() != 0.0f ||
        elisa_ui_viewport_height() != 0.0f) {
        puts("negative viewport was not normalized");
        failures++;
    }

    if (failures == 0) {
        puts("capi: C example passed");
        return 0;
    }
    puts("capi: C example failed");
    return 1;
}
