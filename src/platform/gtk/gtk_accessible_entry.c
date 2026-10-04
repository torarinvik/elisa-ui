#include "gtk_accessible_entry.h"

#if !GTK_CHECK_VERSION(4, 14, 0)
#error "GTK accessible text redaction requires GTK 4.14 or newer"
#endif

typedef struct {
    GtkEntry parent_instance;
    gboolean sensitive;
    guint accessible_length;
} ElisaAccessibleEntry;

typedef struct {
    GtkEntryClass parent_class;
} ElisaAccessibleEntryClass;

static void accessible_text_init(GtkAccessibleTextInterface *iface);
static void on_entry_changed(GtkEditable *editable, gpointer data);

G_DEFINE_TYPE_WITH_CODE(ElisaAccessibleEntry, elisa_accessible_entry,
                        GTK_TYPE_ENTRY,
                        G_IMPLEMENT_INTERFACE(GTK_TYPE_ACCESSIBLE_TEXT,
                                              accessible_text_init))

static ElisaAccessibleEntry *entry_from_accessible(GtkAccessibleText *accessible) {
    return (ElisaAccessibleEntry *)(void *)accessible;
}

static GtkAccessibleText *delegate_accessible_text(
    GtkAccessibleText *accessible) {
    GtkEditable *delegate = gtk_editable_get_delegate(GTK_EDITABLE(accessible));
    return delegate != NULL && GTK_IS_ACCESSIBLE_TEXT(delegate)
               ? GTK_ACCESSIBLE_TEXT(delegate)
               : NULL;
}

static GtkAccessibleTextInterface *delegate_text_interface(
    GtkAccessibleText *accessible) {
    GtkAccessibleText *delegate = delegate_accessible_text(accessible);
    return delegate != NULL ? GTK_ACCESSIBLE_TEXT_GET_IFACE(delegate) : NULL;
}

static GBytes *empty_contents(void) {
    return g_bytes_new_static("", 0);
}

static GBytes *accessible_get_contents(GtkAccessibleText *accessible,
                                       unsigned int start,
                                       unsigned int end) {
    ElisaAccessibleEntry *self = entry_from_accessible(accessible);
    if (self->sensitive) return empty_contents();
    GtkAccessibleTextInterface *delegate = delegate_text_interface(accessible);
    return delegate != NULL && delegate->get_contents != NULL
               ? delegate->get_contents(delegate_accessible_text(accessible),
                                        start, end)
               : empty_contents();
}

static GBytes *accessible_get_contents_at(
    GtkAccessibleText *accessible, unsigned int offset,
    GtkAccessibleTextGranularity granularity, unsigned int *start,
    unsigned int *end) {
    ElisaAccessibleEntry *self = entry_from_accessible(accessible);
    if (self->sensitive) {
        if (start != NULL) *start = 0;
        if (end != NULL) *end = 0;
        return empty_contents();
    }
    GtkAccessibleTextInterface *delegate = delegate_text_interface(accessible);
    return delegate != NULL && delegate->get_contents_at != NULL
               ? delegate->get_contents_at(
                     delegate_accessible_text(accessible), offset,
                     granularity, start, end)
               : empty_contents();
}

static unsigned int accessible_get_caret(GtkAccessibleText *accessible) {
    ElisaAccessibleEntry *self = entry_from_accessible(accessible);
    if (self->sensitive) return 0;
    GtkAccessibleTextInterface *delegate = delegate_text_interface(accessible);
    return delegate != NULL && delegate->get_caret_position != NULL
               ? delegate->get_caret_position(
                     delegate_accessible_text(accessible))
               : 0;
}

static gboolean accessible_get_selection(GtkAccessibleText *accessible,
                                         gsize *n_ranges,
                                         GtkAccessibleTextRange **ranges) {
    ElisaAccessibleEntry *self = entry_from_accessible(accessible);
    if (n_ranges != NULL) *n_ranges = 0;
    if (ranges != NULL) *ranges = NULL;
    if (self->sensitive) return FALSE;
    GtkAccessibleTextInterface *delegate = delegate_text_interface(accessible);
    return delegate != NULL && delegate->get_selection != NULL &&
           delegate->get_selection(delegate_accessible_text(accessible),
                                   n_ranges, ranges);
}

static gboolean accessible_get_attributes(
    GtkAccessibleText *accessible, unsigned int offset, gsize *n_ranges,
    GtkAccessibleTextRange **ranges, char ***attribute_names,
    char ***attribute_values) {
    ElisaAccessibleEntry *self = entry_from_accessible(accessible);
    if (n_ranges != NULL) *n_ranges = 0;
    if (ranges != NULL) *ranges = NULL;
    if (attribute_names != NULL) *attribute_names = NULL;
    if (attribute_values != NULL) *attribute_values = NULL;
    if (self->sensitive) return FALSE;
    GtkAccessibleTextInterface *delegate = delegate_text_interface(accessible);
    return delegate != NULL && delegate->get_attributes != NULL &&
           delegate->get_attributes(delegate_accessible_text(accessible),
                                    offset, n_ranges, ranges, attribute_names,
                                    attribute_values);
}

static void accessible_get_default_attributes(
    GtkAccessibleText *accessible, char ***attribute_names,
    char ***attribute_values) {
    GtkAccessibleTextInterface *delegate = delegate_text_interface(accessible);
    if (delegate != NULL && delegate->get_default_attributes != NULL) {
        delegate->get_default_attributes(
            delegate_accessible_text(accessible),
            attribute_names, attribute_values);
    } else {
        if (attribute_names != NULL) *attribute_names = NULL;
        if (attribute_values != NULL) *attribute_values = NULL;
    }
}

#if GTK_CHECK_VERSION(4, 16, 0)
static gboolean accessible_get_extents(GtkAccessibleText *accessible,
                                       unsigned int start, unsigned int end,
                                       graphene_rect_t *extents) {
    ElisaAccessibleEntry *self = entry_from_accessible(accessible);
    if (self->sensitive) return FALSE;
    GtkAccessibleTextInterface *delegate = delegate_text_interface(accessible);
    return delegate != NULL && delegate->get_extents != NULL &&
           delegate->get_extents(delegate_accessible_text(accessible),
                                 start, end, extents);
}

static gboolean accessible_get_offset(GtkAccessibleText *accessible,
                                      const graphene_point_t *point,
                                      unsigned int *offset) {
    ElisaAccessibleEntry *self = entry_from_accessible(accessible);
    if (self->sensitive) {
        if (offset != NULL) *offset = 0;
        return FALSE;
    }
    GtkAccessibleTextInterface *delegate = delegate_text_interface(accessible);
    return delegate != NULL && delegate->get_offset != NULL &&
           delegate->get_offset(delegate_accessible_text(accessible),
                                point, offset);
}
#endif

static gboolean accessible_set_caret(GtkAccessibleText *accessible,
                                     unsigned int offset) {
    ElisaAccessibleEntry *self = entry_from_accessible(accessible);
    if (self->sensitive) return FALSE;
    gtk_editable_set_position(GTK_EDITABLE(accessible),
                              offset > G_MAXINT ? G_MAXINT : (int)offset);
    return TRUE;
}

static gboolean accessible_set_selection(GtkAccessibleText *accessible,
                                         gsize index,
                                         GtkAccessibleTextRange *range) {
    (void)index;
    if (range == NULL) return FALSE;
    ElisaAccessibleEntry *self = entry_from_accessible(accessible);
    if (self->sensitive) return FALSE;
    gsize start = MIN((gsize)range->start, (gsize)G_MAXINT);
    gsize stop = range->length > (gsize)G_MAXINT - start
                     ? (gsize)G_MAXINT
                     : start + range->length;
    gtk_editable_select_region(
        GTK_EDITABLE(accessible), (int)start, (int)stop);
    return TRUE;
}

static void accessible_text_init(GtkAccessibleTextInterface *iface) {
    iface->get_contents = accessible_get_contents;
    iface->get_contents_at = accessible_get_contents_at;
    iface->get_caret_position = accessible_get_caret;
    iface->get_selection = accessible_get_selection;
    iface->get_attributes = accessible_get_attributes;
    iface->get_default_attributes = accessible_get_default_attributes;
#if GTK_CHECK_VERSION(4, 16, 0)
    iface->get_extents = accessible_get_extents;
    iface->get_offset = accessible_get_offset;
#endif
#if GTK_CHECK_VERSION(4, 22, 0)
    iface->set_caret_position = accessible_set_caret;
    iface->set_selection = accessible_set_selection;
#endif
}

static guint accessible_length(GtkEditable *editable) {
    const char *text = gtk_editable_get_text(editable);
    glong length = text == NULL ? 0 : g_utf8_strlen(text, -1);
    return length > G_MAXUINT ? G_MAXUINT : (guint)length;
}

static void publish_contents_change(ElisaAccessibleEntry *self,
                                    GtkAccessibleTextContentChange change,
                                    guint length) {
    if (length == 0) return;
    gtk_accessible_text_update_contents(GTK_ACCESSIBLE_TEXT(self), change,
                                        0, length);
}

static void on_entry_changed(GtkEditable *editable, gpointer data) {
    (void)data;
    ElisaAccessibleEntry *self = (ElisaAccessibleEntry *)(void *)editable;
    if (self->sensitive) return;
    guint length = accessible_length(editable);
    publish_contents_change(self, GTK_ACCESSIBLE_TEXT_CONTENT_CHANGE_REMOVE,
                            self->accessible_length);
    publish_contents_change(self, GTK_ACCESSIBLE_TEXT_CONTENT_CHANGE_INSERT,
                            length);
    self->accessible_length = length;
}

static void elisa_accessible_entry_class_init(ElisaAccessibleEntryClass *klass) {
    gtk_widget_class_set_accessible_role(GTK_WIDGET_CLASS(klass),
                                         GTK_ACCESSIBLE_ROLE_TEXT_BOX);
}

static void elisa_accessible_entry_init(ElisaAccessibleEntry *self) {
    self->sensitive = FALSE;
    self->accessible_length = 0;
    g_signal_connect(self, "changed", G_CALLBACK(on_entry_changed), NULL);
}

GtkWidget *elisa_gtk_accessible_entry_new(int32_t secure) {
    GtkWidget *widget = g_object_new(elisa_accessible_entry_get_type(), NULL);
    gtk_entry_set_visibility(GTK_ENTRY(widget), secure == 0);
    return widget;
}

void elisa_gtk_accessible_entry_set_sensitive(
    GtkWidget *widget, int32_t accessibility_sensitive) {
    if (widget == NULL || !G_TYPE_CHECK_INSTANCE_TYPE(
                              widget, elisa_accessible_entry_get_type())) return;
    ElisaAccessibleEntry *self = (ElisaAccessibleEntry *)(void *)widget;
    gboolean sensitive = accessibility_sensitive != 0;
    if (self->sensitive == sensitive) return;
    if (sensitive) {
        guint old_length = self->accessible_length;
        self->sensitive = TRUE;
        self->accessible_length = 0;
        g_object_set_data(G_OBJECT(widget), "elisa-accessibility-sensitive",
                          GINT_TO_POINTER(TRUE));
        publish_contents_change(self, GTK_ACCESSIBLE_TEXT_CONTENT_CHANGE_REMOVE,
                                old_length);
    } else {
        guint length = accessible_length(GTK_EDITABLE(widget));
        self->sensitive = FALSE;
        self->accessible_length = length;
        g_object_set_data(G_OBJECT(widget), "elisa-accessibility-sensitive",
                          GINT_TO_POINTER(FALSE));
        publish_contents_change(self, GTK_ACCESSIBLE_TEXT_CONTENT_CHANGE_INSERT,
                                length);
    }
}
