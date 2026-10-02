#include "elisa_ui.h"

void elisa_ui_on_init(void) {}
void elisa_ui_on_event(const elisa_ui_event *event) { (void)event; }
void elisa_ui_on_text_input(const char *text, size_t length) {
    (void)text;
    (void)length;
}
void elisa_ui_on_text_editing(const char *text, size_t length,
                              int32_t selected_start,
                              int32_t selected_length) {
    (void)text;
    (void)length;
    (void)selected_start;
    (void)selected_length;
}
void elisa_ui_on_frame(void) {}
void elisa_ui_on_widget_event(elisa_ui_widget_handle widget, int32_t event) {
    (void)widget;
    (void)event;
}
