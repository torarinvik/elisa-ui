// elisa-ui GTK backend: the widget tree as real GTK controls.
//
// THE LINUX HALF OF THE NATIVE STORY. The seam's mapping table has carried a
// GTK column since it was written, for a backend that did not exist -- Windows
// and Linux had the Skia canvas through SDL3 and nothing else, while macOS,
// iOS and Android each got real controls. This is that column becoming code.
//
// GTK is a C API, so unlike the Cocoa shim there is no objc_msgSend prototype
// problem to solve here; this file exists for the same reason the others do --
// to keep every typed decision in Elisa and hand the toolkit only values it
// has already chosen.
//
// ABSOLUTE PLACEMENT ON A GtkFixed. Every backend in this framework places
// controls at the boxes UiWidgets::layout already computed, so the container
// has to accept coordinates rather than impose its own. GtkFixed is the one
// GTK container that does. Delegating to GtkBox or a GtkGrid is the same
// per-backend upgrade the seam's header leaves open for Auto Layout.

#include <gtk/gtk.h>
#include <stdint.h>
#include <string.h>

// The handle Elisa holds is the GtkWidget pointer. GTK owns the lifetime once
// a widget is parented, which is why nothing here retains: the seam's arena
// carries the identity and this file never keeps a second table.
static GtkWidget *widget_of(size_t handle) {
    return (GtkWidget *)(void *)handle;
}

int32_t elisa_gtk_init(void) {
    // gtk_init_check rather than gtk_init: a machine with no display should
    // give this backend a false rather than abort the process, which is what
    // lets a headless gate say "skipped" instead of dying.
    return gtk_init_check() ? 1 : 0;
}

size_t elisa_gtk_create_window(int32_t resizable) {
    GtkWidget *window = gtk_window_new();
    gtk_window_set_resizable(GTK_WINDOW(window), resizable != 0);
    // One GtkFixed as the content, so a child can be placed at the box the
    // framework computed rather than wherever a box layout would put it.
    gtk_window_set_child(GTK_WINDOW(window), gtk_fixed_new());
    return (size_t)(void *)window;
}

size_t elisa_gtk_create_panel(void) { return (size_t)(void *)gtk_fixed_new(); }

size_t elisa_gtk_create_scroll(int32_t vertical) {
    GtkWidget *scroll = gtk_scrolled_window_new();
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll),
                                   vertical ? GTK_POLICY_NEVER : GTK_POLICY_AUTOMATIC,
                                   vertical ? GTK_POLICY_AUTOMATIC : GTK_POLICY_NEVER);
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), gtk_fixed_new());
    return (size_t)(void *)scroll;
}

size_t elisa_gtk_create_label(void) {
    GtkWidget *label = gtk_label_new(NULL);
    // One line, ending in an ellipsis: the same answer to a box too small that
    // every other backend here gives, and that the painted ones always gave.
    gtk_label_set_ellipsize(GTK_LABEL(label), PANGO_ELLIPSIZE_END);
    gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
    return (size_t)(void *)label;
}

size_t elisa_gtk_create_button(void) { return (size_t)(void *)gtk_button_new(); }
size_t elisa_gtk_create_check(void) { return (size_t)(void *)gtk_check_button_new(); }

// A radio in GTK4 is a check button in a group, and the group is the list's
// knowledge rather than the toolkit's -- the seam already turns siblings off,
// so each one stands alone here and the framework stays the single authority.
size_t elisa_gtk_create_radio(void) {
    GtkWidget *radio = gtk_check_button_new();
    gtk_check_button_set_group(GTK_CHECK_BUTTON(radio), NULL);
    return (size_t)(void *)radio;
}

size_t elisa_gtk_create_entry(int32_t secure) {
    GtkWidget *entry = gtk_entry_new();
    // SECURE IS A PROPERTY HERE, as on iOS and Android -- AppKit is the one
    // platform that needs a different class, which is why the fact travels in
    // ControlState and every backend sees it at create.
    gtk_entry_set_visibility(GTK_ENTRY(entry), secure == 0);
    return (size_t)(void *)entry;
}

size_t elisa_gtk_create_slider(double low, double high, double value) {
    GtkWidget *scale = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, low, high,
                                                (high - low) / 1000.0);
    gtk_range_set_value(GTK_RANGE(scale), value);
    gtk_scale_set_draw_value(GTK_SCALE(scale), FALSE);
    return (size_t)(void *)scale;
}

size_t elisa_gtk_create_progress(void) { return (size_t)(void *)gtk_progress_bar_new(); }

// The fixed inside a window or a scroller is where children go; everything
// else parents directly. Elisa never learns that distinction.
static GtkWidget *content_of(GtkWidget *parent) {
    if (GTK_IS_WINDOW(parent)) return gtk_window_get_child(GTK_WINDOW(parent));
    if (GTK_IS_SCROLLED_WINDOW(parent)) return gtk_scrolled_window_get_child(GTK_SCROLLED_WINDOW(parent));
    return parent;
}

void elisa_gtk_add_child(size_t parent, size_t child) {
    GtkWidget *into = content_of(widget_of(parent));
    if (into == NULL || !GTK_IS_FIXED(into)) return;
    gtk_fixed_put(GTK_FIXED(into), widget_of(child), 0.0, 0.0);
}

void elisa_gtk_set_frame(size_t handle, float x, float y, float width, float height) {
    GtkWidget *widget = widget_of(handle);
    if (widget == NULL) return;
    if (GTK_IS_WINDOW(widget)) {
        gtk_window_set_default_size(GTK_WINDOW(widget), (int)width, (int)height);
        return;
    }
    gtk_widget_set_size_request(widget, (int)width, (int)height);
    GtkWidget *parent = gtk_widget_get_parent(widget);
    if (parent != NULL && GTK_IS_FIXED(parent)) {
        gtk_fixed_move(GTK_FIXED(parent), widget, x, y);
    }
}

void elisa_gtk_set_label_text(size_t handle, const char *text) {
    GtkWidget *widget = widget_of(handle);
    if (GTK_IS_LABEL(widget)) gtk_label_set_text(GTK_LABEL(widget), text == NULL ? "" : text);
    else if (GTK_IS_BUTTON(widget)) gtk_button_set_label(GTK_BUTTON(widget), text == NULL ? "" : text);
    else if (GTK_IS_CHECK_BUTTON(widget)) gtk_check_button_set_label(GTK_CHECK_BUTTON(widget), text == NULL ? "" : text);
    else if (GTK_IS_ENTRY(widget)) {
        gtk_editable_set_text(GTK_EDITABLE(widget), text == NULL ? "" : text);
    }
}

void elisa_gtk_set_help(size_t handle, const char *placeholder, const char *help) {
    GtkWidget *widget = widget_of(handle);
    if (widget == NULL) return;
    if (GTK_IS_ENTRY(widget) && placeholder != NULL) {
        gtk_entry_set_placeholder_text(GTK_ENTRY(widget), placeholder);
    }
    // GTK's accessibility is a property on the widget itself, which is the
    // same shape as UIKit's accessibilityHint and Android's contentDescription.
    if (help != NULL && help[0] != '\0') {
        gtk_accessible_update_property(GTK_ACCESSIBLE(widget),
                                       GTK_ACCESSIBLE_PROPERTY_DESCRIPTION, help, -1);
    }
}

void elisa_gtk_set_state(size_t handle, float value, int32_t selected,
                         int32_t enabled, int32_t secure) {
    GtkWidget *widget = widget_of(handle);
    if (widget == NULL) return;
    gtk_widget_set_sensitive(widget, enabled != 0);
    if (GTK_IS_CHECK_BUTTON(widget)) gtk_check_button_set_active(GTK_CHECK_BUTTON(widget), selected != 0);
    else if (GTK_IS_RANGE(widget)) gtk_range_set_value(GTK_RANGE(widget), value);
    else if (GTK_IS_PROGRESS_BAR(widget)) gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(widget), value);
    else if (GTK_IS_ENTRY(widget)) gtk_entry_set_visibility(GTK_ENTRY(widget), secure == 0);
}

// Elisa resolves the widget back to a control index and decides what the
// action means; this only reports that one happened.
extern int32_t elisa_gtk_action(size_t handle, float value, int32_t selected);

static void on_clicked(GtkButton *button, gpointer data) {
    (void)data;
    (void)elisa_gtk_action((size_t)(void *)button, 0.0f, 0);
}

static void on_toggled(GtkCheckButton *check, gpointer data) {
    (void)data;
    (void)elisa_gtk_action((size_t)(void *)check, 0.0f,
                           gtk_check_button_get_active(check) ? 1 : 0);
}

static void on_value_changed(GtkRange *range, gpointer data) {
    (void)data;
    (void)elisa_gtk_action((size_t)(void *)range, (float)gtk_range_get_value(range), 0);
}

static void on_entry_changed(GtkEditable *editable, gpointer data) {
    (void)data;
    extern int32_t elisa_gtk_text_action(size_t handle, const char *text);
    (void)elisa_gtk_text_action((size_t)(void *)editable, gtk_editable_get_text(editable));
}

void elisa_gtk_set_action(size_t handle) {
    GtkWidget *widget = widget_of(handle);
    if (GTK_IS_CHECK_BUTTON(widget)) g_signal_connect(widget, "toggled", G_CALLBACK(on_toggled), NULL);
    else if (GTK_IS_BUTTON(widget)) g_signal_connect(widget, "clicked", G_CALLBACK(on_clicked), NULL);
    else if (GTK_IS_RANGE(widget)) g_signal_connect(widget, "value-changed", G_CALLBACK(on_value_changed), NULL);
    else if (GTK_IS_EDITABLE(widget)) g_signal_connect(widget, "changed", G_CALLBACK(on_entry_changed), NULL);
}

// Facts that can only be read from a live widget, for the fixture that asserts
// them -- the same role appkit_shim.m's inspection entries play.
int32_t elisa_gtk_is_type(size_t handle, const char *name) {
    GtkWidget *widget = widget_of(handle);
    if (widget == NULL || name == NULL) return 0;
    return strcmp(G_OBJECT_TYPE_NAME(widget), name) == 0 ? 1 : 0;
}

int32_t elisa_gtk_is_sensitive(size_t handle) {
    GtkWidget *widget = widget_of(handle);
    return widget == NULL ? -1 : (gtk_widget_get_sensitive(widget) ? 1 : 0);
}

int32_t elisa_gtk_check_is_active(size_t handle) {
    GtkWidget *widget = widget_of(handle);
    if (!GTK_IS_CHECK_BUTTON(widget)) return -1;
    return gtk_check_button_get_active(GTK_CHECK_BUTTON(widget)) ? 1 : 0;
}

int32_t elisa_gtk_entry_is_visible_text(size_t handle) {
    GtkWidget *widget = widget_of(handle);
    if (!GTK_IS_ENTRY(widget)) return -1;
    return gtk_entry_get_visibility(GTK_ENTRY(widget)) ? 1 : 0;
}

int32_t elisa_gtk_entry_has_placeholder(size_t handle) {
    GtkWidget *widget = widget_of(handle);
    if (!GTK_IS_ENTRY(widget)) return -1;
    const char *text = gtk_entry_get_placeholder_text(GTK_ENTRY(widget));
    return (text != NULL && text[0] != '\0') ? 1 : 0;
}

int32_t elisa_gtk_child_count(size_t handle) {
    GtkWidget *widget = content_of(widget_of(handle));
    if (widget == NULL) return -1;
    int32_t count = 0;
    for (GtkWidget *child = gtk_widget_get_first_child(widget); child != NULL;
         child = gtk_widget_get_next_sibling(child)) {
        count += 1;
    }
    return count;
}

void elisa_gtk_destroy_window(size_t handle) {
    GtkWidget *widget = widget_of(handle);
    if (GTK_IS_WINDOW(widget)) gtk_window_destroy(GTK_WINDOW(widget));
}
