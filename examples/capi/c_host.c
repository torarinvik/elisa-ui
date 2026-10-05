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
static int embedded_nul_text_count;
static int editing_count;
static int32_t editing_start;
static int32_t editing_length;
static elisa_ui_widget_handle last_widget;
static int32_t last_widget_event;
static int widget_event_count;

void elisa_ui_on_init(void) {}
void elisa_ui_on_frame(void) {}
void elisa_ui_on_widget_event(elisa_ui_widget_handle widget, int32_t event) {
    last_widget = widget;
    last_widget_event = event;
    widget_event_count++;
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
    if (length == 3 && text[0] == 'A' && text[1] == '\0' && text[2] == 'B') {
        embedded_nul_text_count++;
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

    elisa_ui_widget_tree_reset();
    elisa_ui_set_viewport(360.0f, 220.0f);
    elisa_ui_widget_handle root = elisa_ui_widget_column(
        ELISA_UI_WIDGET_ROOT_PARENT, 8.0f, 4.0f, UINT32_C(0x202028ff));
    elisa_ui_widget_handle row = elisa_ui_widget_row(
        root, 0.0f, 8.0f, UINT32_C(0x202028ff));
    elisa_ui_widget_handle vertical_scroll = elisa_ui_widget_vertical_scroll(
        row, 180.0f, 100.0f, UINT32_C(0x202028ff));
    elisa_ui_widget_handle horizontal_scroll = elisa_ui_widget_horizontal_scroll(
        row, 180.0f, 100.0f, UINT32_C(0x202028ff));
    elisa_ui_widget_handle label = elisa_ui_widget_label(
        row, "Status", strlen("Status"), 16.0f, UINT32_C(0xffffffff));
    elisa_ui_widget_handle button = elisa_ui_widget_button(
        row, 120.0f, 36.0f, UINT32_C(0x303038ff),
        UINT32_C(0x404048ff), UINT32_C(0x505058ff));
    elisa_ui_widget_handle checkbox = elisa_ui_widget_check_box(
        row, 24.0f, 24.0f, UINT32_C(0x303038ff),
        UINT32_C(0x404048ff), UINT32_C(0x505058ff));
    elisa_ui_widget_handle radio = elisa_ui_widget_radio_button(
        row, 24.0f, 24.0f, UINT32_C(0x303038ff),
        UINT32_C(0x404048ff), UINT32_C(0x505058ff));
    elisa_ui_widget_handle slider = elisa_ui_widget_slider(
        row, 160.0f, 24.0f, 0.25f, UINT32_C(0x303038ff),
        UINT32_C(0x404048ff), UINT32_C(0x505058ff));
    elisa_ui_widget_handle progress = elisa_ui_widget_progress_bar(
        row, 160.0f, 12.0f, 0.5f, UINT32_C(0x303038ff), UINT32_C(0x404048ff));
    elisa_ui_widget_handle field = elisa_ui_widget_text_field(
        row, "Hi é", strlen("Hi é"), 180.0f, 32.0f, 16.0f,
        UINT32_C(0xffffffff), UINT32_C(0x202028ff));
    elisa_ui_widget_handle secure_field = elisa_ui_widget_secure_text_field(
        row, "secret", 6, 180.0f, 32.0f, 16.0f,
        UINT32_C(0xffffffff), UINT32_C(0x202028ff));
    elisa_ui_widget_handle list = elisa_ui_widget_virtual_list(
        root, "Items", strlen("Items"), 5, 20.0f, 2.0f, 180.0f, 64.0f,
        UINT32_C(0x202028ff));
    elisa_ui_widget_handle list_row_a = elisa_ui_widget_button(
        list, 120.0f, 20.0f, UINT32_C(0x303038ff),
        UINT32_C(0x404048ff), UINT32_C(0x505058ff));
    elisa_ui_widget_handle list_row_b = elisa_ui_widget_button(
        list, 120.0f, 20.0f, UINT32_C(0x303038ff),
        UINT32_C(0x404048ff), UINT32_C(0x505058ff));
    elisa_ui_widget_handle carousel = elisa_ui_widget_horizontal_virtual_list(
        root, "Carousel", strlen("Carousel"), 3, 36.0f, 6.0f, 180.0f, 64.0f,
        UINT32_C(0x202028ff));
    elisa_ui_set_viewport(360.0f, 220.0f);
    if (!elisa_ui_widget_is_valid(root) || !elisa_ui_widget_is_valid(row) ||
        !elisa_ui_widget_is_valid(vertical_scroll) || !elisa_ui_widget_is_valid(horizontal_scroll) ||
        !elisa_ui_widget_is_valid(label) || !elisa_ui_widget_is_valid(button) ||
        !elisa_ui_widget_is_valid(checkbox) || !elisa_ui_widget_is_valid(radio) ||
        !elisa_ui_widget_is_valid(slider) || !elisa_ui_widget_is_valid(progress) ||
        !elisa_ui_widget_is_valid(field) || !elisa_ui_widget_is_valid(secure_field) ||
        !elisa_ui_widget_is_valid(list) ||
        !elisa_ui_widget_is_valid(list_row_a) || !elisa_ui_widget_is_valid(list_row_b) ||
        !elisa_ui_widget_is_valid(carousel) ||
        elisa_ui_widget_set_text(button, "Run", 3, 16.0f,
                                 UINT32_C(0xffffffff)) != 1) {
        puts("C app could not construct and label retained controls");
        failures++;
    }
    if (elisa_ui_widget_scroll_offset(vertical_scroll) != 0.0f ||
        elisa_ui_widget_scroll_offset(horizontal_scroll) != 0.0f ||
        elisa_ui_widget_set_scroll_offset(button, 1.0f) != 0) {
        puts("C app scroll controls did not expose safe logical offsets");
        failures++;
    }
    int32_t list_count_before = elisa_ui_widget_virtual_item_count(list);
    int32_t list_scrolled = elisa_ui_widget_virtual_scroll_to(list, 3);
    int32_t list_count_changed = elisa_ui_widget_set_virtual_item_count(list, 8);
    int32_t list_count_after = elisa_ui_widget_virtual_item_count(list);
    int32_t wrong_kind_virtual_scroll = elisa_ui_widget_virtual_scroll_to(button, 1);
    if (elisa_ui_widget_virtual_item_count(carousel) != 3 ||
        list_count_before != 5 || list_scrolled != 1 || list_count_changed != 1 ||
        list_count_after != 8 || wrong_kind_virtual_scroll != 0) {
        puts("C app virtual-list row-pool lifecycle did not survive rebinding");
        failures++;
    }
    if (elisa_ui_widget_set_selected(checkbox, 1) != 1 ||
        elisa_ui_widget_selected(checkbox) != 1 ||
        elisa_ui_widget_set_selected(radio, 1) != 1 ||
        elisa_ui_widget_selected(radio) != 1 ||
        elisa_ui_widget_set_selected(button, 1) != 0 ||
        elisa_ui_widget_set_value(slider, 1.25f) != 1 ||
        elisa_ui_widget_value(slider) != 1.0f ||
        elisa_ui_widget_set_value(progress, -0.5f) != 1 ||
        elisa_ui_widget_value(progress) != 0.0f ||
        elisa_ui_widget_set_value(button, 0.5f) != 0) {
        puts("C app selection/value controls did not enforce their types and ranges");
        failures++;
    }
    char field_text[8] = {0};
    if (elisa_ui_widget_request_text_focus(field) != 1 ||
        elisa_ui_widget_text_length(field) != 5 ||
        elisa_ui_widget_copy_text(field, field_text, 4) != 3 ||
        memcmp(field_text, "Hi ", 3) != 0 ||
        elisa_ui_widget_copy_text(field, field_text, sizeof(field_text)) != 5 ||
        memcmp(field_text, "Hi é", 5) != 0 ||
        elisa_ui_widget_text_length(button) != -1 ||
        elisa_ui_widget_request_text_focus(button) != 0 ||
        elisa_ui_widget_set_selection(field, 3, 5) != 1 ||
        elisa_ui_widget_selection_start(field) != 3 ||
        elisa_ui_widget_selection_end(field) != 5 ||
        elisa_ui_widget_set_input_text(field, "Hi é!", strlen("Hi é!")) != 1 ||
        elisa_ui_widget_text_length(field) != 6 ||
        elisa_ui_widget_copy_text(field, field_text, sizeof(field_text)) != 6 ||
        memcmp(field_text, "Hi é!", 6) != 0 ||
        elisa_ui_widget_request_text_focus(secure_field) != 1 ||
        elisa_ui_widget_set_input_text(secure_field, "changed", 7) != 1 ||
        elisa_ui_widget_text_length(secure_field) != -1 ||
        elisa_ui_widget_copy_text(secure_field, field_text, sizeof(field_text)) != 0 ||
        elisa_ui_widget_selection_start(secure_field) != -1) {
        puts("C app text-field focus/value copy did not preserve bounded UTF-8");
        failures++;
    }
    if (elisa_ui_widget_activate(button) != 1 || widget_event_count == 0 ||
        last_widget != button || last_widget_event != 0) {
        puts("C app control activation did not return an opaque callback token");
        failures++;
    }
    int widget_event_count_after_activation = widget_event_count;
    elisa_ui_widget_tree_reset();
    if (elisa_ui_widget_is_valid(root) || elisa_ui_widget_is_valid(row) ||
        elisa_ui_widget_is_valid(vertical_scroll) || elisa_ui_widget_is_valid(horizontal_scroll) ||
        elisa_ui_widget_is_valid(label) || elisa_ui_widget_is_valid(button) ||
        elisa_ui_widget_is_valid(checkbox) || elisa_ui_widget_is_valid(radio) ||
        elisa_ui_widget_is_valid(slider) || elisa_ui_widget_is_valid(progress) ||
        elisa_ui_widget_is_valid(field) || elisa_ui_widget_is_valid(secure_field) ||
        elisa_ui_widget_is_valid(list) ||
        elisa_ui_widget_is_valid(list_row_a) || elisa_ui_widget_is_valid(list_row_b) ||
        elisa_ui_widget_is_valid(carousel) ||
        elisa_ui_widget_set_enabled(button, 0) != 0 ||
        elisa_ui_widget_set_selected(checkbox, 1) != 0 ||
        elisa_ui_widget_set_value(slider, 0.5f) != 0 ||
        elisa_ui_widget_set_scroll_offset(vertical_scroll, 1.0f) != 0 ||
        elisa_ui_widget_set_virtual_item_count(list, 9) != 0 ||
        elisa_ui_widget_text_length(field) != -1 ||
        elisa_ui_widget_request_text_focus(field) != 0 ||
        elisa_ui_widget_set_input_text(secure_field, "x", 1) != 0 ||
        elisa_ui_widget_activate(button) != 0 || widget_event_count != widget_event_count_after_activation) {
        puts("C app tree reset did not invalidate prior handles");
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

    /* Counted UTF-8 permits U+0000; it is not a C-string terminator here. */
    const char embedded_nul_text[] = {'A', '\0', 'B'};
    elisa_ui_dispatch_text_input(embedded_nul_text, sizeof(embedded_nul_text));
    if (embedded_nul_text_count != 1) {
        puts("embedded NUL in counted UTF-8 text did not survive");
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
    char oversized_text[ELISA_UI_MAX_TEXT_BYTES + 8];
    memset(oversized_text, 'x', sizeof(oversized_text));
    elisa_ui_dispatch_text_input(oversized_text, sizeof(oversized_text));
    if (last_text_length != ELISA_UI_MAX_TEXT_BYTES) {
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
