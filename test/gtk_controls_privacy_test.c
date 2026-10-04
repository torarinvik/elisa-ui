#include <gtk/gtk.h>
#include <stdint.h>
#include <stdio.h>

void elisa_gtk_set_help(size_t handle, const char *placeholder, const char *help);
size_t elisa_gtk_create_entry(int32_t secure);
void elisa_gtk_set_state(size_t handle, float value, int32_t selected,
                         int32_t enabled, int32_t secure,
                         int32_t accessibility_sensitive);

int32_t elisa_gtk_action(size_t handle, float value, int32_t selected) {
    (void)handle;
    (void)value;
    (void)selected;
    return 0;
}

int32_t elisa_gtk_text_action(size_t handle, const char *text) {
    (void)handle;
    (void)text;
    return 0;
}

static size_t handle_of(GtkWidget *widget) {
    return (size_t)(void *)widget;
}

static char *accessible_text(GtkWidget *widget) {
    GtkAccessibleTextInterface *iface =
        GTK_ACCESSIBLE_TEXT_GET_IFACE(widget);
    GBytes *bytes = iface->get_contents(GTK_ACCESSIBLE_TEXT(widget), 0,
                                        G_MAXUINT);
    g_assert_nonnull(bytes);
    gsize length = 0;
    gconstpointer data = g_bytes_get_data(bytes, &length);
    char *text = g_strndup(data, length);
    g_bytes_unref(bytes);
    return text;
}

static void set_sensitive(GtkWidget *widget, gboolean sensitive,
                          float value, gboolean selected) {
    elisa_gtk_set_state(handle_of(widget), value, selected, TRUE, FALSE,
                        sensitive);
}

int main(void) {
    if (!gtk_init_check()) {
        puts("gtk-controls-privacy: skipped (no display)");
        return 0;
    }

    GtkWidget *label = gtk_label_new("Visible label text");
    g_object_ref_sink(label);
    set_sensitive(label, TRUE, 0.0f, FALSE);
    gtk_test_accessible_assert_property(GTK_ACCESSIBLE(label),
                                        GTK_ACCESSIBLE_PROPERTY_LABEL,
                                        "Sensitive content");
    g_assert_cmpstr(gtk_label_get_text(GTK_LABEL(label)), ==, "Visible label text");
    set_sensitive(label, FALSE, 0.0f, FALSE);
    g_assert_false(gtk_test_accessible_has_property(GTK_ACCESSIBLE(label),
                                                    GTK_ACCESSIBLE_PROPERTY_LABEL));

    GtkWidget *button = gtk_button_new_with_label("Visible button text");
    g_object_ref_sink(button);
    set_sensitive(button, TRUE, 0.0f, FALSE);
    gtk_test_accessible_assert_property(GTK_ACCESSIBLE(button),
                                        GTK_ACCESSIBLE_PROPERTY_LABEL,
                                        "Sensitive content");
    g_assert_cmpstr(gtk_button_get_label(GTK_BUTTON(button)), ==,
                    "Visible button text");

    GtkWidget *entry = GTK_WIDGET((void *)elisa_gtk_create_entry(FALSE));
    g_object_ref_sink(entry);
    gtk_editable_set_text(GTK_EDITABLE(entry), "visible entry text");
    g_assert_true(GTK_IS_ACCESSIBLE_TEXT(entry));
    GtkAccessibleTextInterface *text_iface =
        GTK_ACCESSIBLE_TEXT_GET_IFACE(entry);
    char *text = accessible_text(entry);
    g_assert_cmpstr(text, ==, "visible entry text");
    g_free(text);
#if GTK_CHECK_VERSION(4, 22, 0)
    g_assert_true(text_iface->set_caret_position(GTK_ACCESSIBLE_TEXT(entry), 3));
    g_assert_cmpuint(text_iface->get_caret_position(GTK_ACCESSIBLE_TEXT(entry)),
                     ==, 3);
    GtkAccessibleTextRange requested_range = {.start = 1, .length = 4};
    g_assert_true(text_iface->set_selection(GTK_ACCESSIBLE_TEXT(entry), 0,
                                            &requested_range));
    gsize ordinary_selection_count = 0;
    GtkAccessibleTextRange *ordinary_selection = NULL;
    g_assert_true(text_iface->get_selection(GTK_ACCESSIBLE_TEXT(entry),
                                            &ordinary_selection_count,
                                            &ordinary_selection));
    g_assert_cmpuint(ordinary_selection_count, ==, 1);
    g_assert_cmpuint(ordinary_selection[0].start, ==, 1);
    g_assert_cmpuint(ordinary_selection[0].length, ==, 4);
    g_free(ordinary_selection);
#endif
    elisa_gtk_set_help(handle_of(entry), "name@example.org", "Private hint");
    set_sensitive(entry, TRUE, 0.0f, FALSE);
    g_assert_cmpint(GPOINTER_TO_INT(g_object_get_data(
                        G_OBJECT(entry), "elisa-accessibility-sensitive")), ==, 1);
    elisa_gtk_set_help(handle_of(entry), "name@example.org", "Private hint");
    gtk_test_accessible_assert_property(GTK_ACCESSIBLE(entry),
                                        GTK_ACCESSIBLE_PROPERTY_LABEL,
                                        "Sensitive content");
    const char *placeholder = gtk_entry_get_placeholder_text(GTK_ENTRY(entry));
    g_assert_true(placeholder == NULL || placeholder[0] == '\0');
    g_assert_false(gtk_test_accessible_has_property(GTK_ACCESSIBLE(entry),
                                                    GTK_ACCESSIBLE_PROPERTY_DESCRIPTION));
    g_assert_false(gtk_test_accessible_has_property(GTK_ACCESSIBLE(entry),
                                                    GTK_ACCESSIBLE_PROPERTY_PLACEHOLDER));
    g_assert_cmpstr(gtk_editable_get_text(GTK_EDITABLE(entry)), ==,
                    "visible entry text");
    text = accessible_text(entry);
    g_assert_cmpstr(text, ==, "");
    g_free(text);
    g_assert_cmpuint(text_iface->get_caret_position(
                         GTK_ACCESSIBLE_TEXT(entry)), ==, 0);
    gsize selection_count = 0;
    GtkAccessibleTextRange *selection_ranges = NULL;
    g_assert_false(text_iface->get_selection(GTK_ACCESSIBLE_TEXT(entry),
                                             &selection_count,
                                             &selection_ranges));
    g_assert_cmpuint(selection_count, ==, 0);
    g_assert_null(selection_ranges);
#if GTK_CHECK_VERSION(4, 22, 0)
    g_assert_false(text_iface->set_caret_position(GTK_ACCESSIBLE_TEXT(entry),
                                                  3));
    g_assert_false(text_iface->set_selection(GTK_ACCESSIBLE_TEXT(entry), 0,
                                             &requested_range));
#endif
    unsigned int range_start = 9;
    unsigned int range_end = 9;
    GBytes *range_bytes = text_iface->get_contents_at(
        GTK_ACCESSIBLE_TEXT(entry), 0, GTK_ACCESSIBLE_TEXT_GRANULARITY_WORD,
        &range_start, &range_end);
    g_assert_nonnull(range_bytes);
    g_assert_cmpuint(g_bytes_get_size(range_bytes), ==, 0);
    g_assert_cmpuint(range_start, ==, 0);
    g_assert_cmpuint(range_end, ==, 0);
    g_bytes_unref(range_bytes);

    gtk_editable_set_text(GTK_EDITABLE(entry), "replacement secret");
    g_assert_cmpstr(gtk_editable_get_text(GTK_EDITABLE(entry)), ==,
                    "replacement secret");
    text = accessible_text(entry);
    g_assert_cmpstr(text, ==, "");
    g_free(text);
    set_sensitive(entry, FALSE, 0.0f, FALSE);
    elisa_gtk_set_help(handle_of(entry), "name@example.org", "Private hint");
    g_assert_cmpstr(gtk_entry_get_placeholder_text(GTK_ENTRY(entry)), ==,
                    "name@example.org");
    gtk_test_accessible_assert_property(GTK_ACCESSIBLE(entry),
                                        GTK_ACCESSIBLE_PROPERTY_DESCRIPTION,
                                        "Private hint");
    text = accessible_text(entry);
    g_assert_cmpstr(text, ==, "replacement secret");
    g_free(text);

    GtkWidget *range = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL,
                                                 0.0, 10.0, 0.1);
    g_object_ref_sink(range);
    gtk_range_set_value(GTK_RANGE(range), 7.0);
    set_sensitive(range, TRUE, 7.0f, FALSE);
    gtk_test_accessible_assert_property(GTK_ACCESSIBLE(range),
                                        GTK_ACCESSIBLE_PROPERTY_LABEL,
                                        "Sensitive content");
    gtk_test_accessible_assert_property(GTK_ACCESSIBLE(range),
                                        GTK_ACCESSIBLE_PROPERTY_VALUE_MIN, 0.0);
    gtk_test_accessible_assert_property(GTK_ACCESSIBLE(range),
                                        GTK_ACCESSIBLE_PROPERTY_VALUE_MAX, 0.0);
    gtk_test_accessible_assert_property(GTK_ACCESSIBLE(range),
                                        GTK_ACCESSIBLE_PROPERTY_VALUE_NOW, 0.0);
    g_assert_cmpfloat(gtk_range_get_value(GTK_RANGE(range)), ==, 7.0);
    set_sensitive(range, FALSE, 7.0f, FALSE);
    g_assert_cmpfloat(gtk_range_get_value(GTK_RANGE(range)), ==, 7.0);
    gtk_test_accessible_assert_property(GTK_ACCESSIBLE(range),
                                        GTK_ACCESSIBLE_PROPERTY_VALUE_MIN, 0.0);
    gtk_test_accessible_assert_property(GTK_ACCESSIBLE(range),
                                        GTK_ACCESSIBLE_PROPERTY_VALUE_MAX, 10.0);
    gtk_test_accessible_assert_property(GTK_ACCESSIBLE(range),
                                        GTK_ACCESSIBLE_PROPERTY_VALUE_NOW, 7.0);

    GtkWidget *check = gtk_check_button_new();
    g_object_ref_sink(check);
    set_sensitive(check, TRUE, 0.0f, TRUE);
    gtk_test_accessible_assert_state(GTK_ACCESSIBLE(check),
                                     GTK_ACCESSIBLE_STATE_CHECKED,
                                     GTK_ACCESSIBLE_TRISTATE_FALSE);
    g_assert_true(gtk_check_button_get_active(GTK_CHECK_BUTTON(check)));
    set_sensitive(check, FALSE, 0.0f, TRUE);
    g_assert_true(gtk_check_button_get_active(GTK_CHECK_BUTTON(check)));
    gtk_test_accessible_assert_state(GTK_ACCESSIBLE(check),
                                     GTK_ACCESSIBLE_STATE_CHECKED,
                                     GTK_ACCESSIBLE_TRISTATE_TRUE);

    g_object_unref(label);
    g_object_unref(button);
    g_object_unref(entry);
    g_object_unref(range);
    g_object_unref(check);
    puts("gtk-controls-privacy: all checks passed");
    return 0;
}
