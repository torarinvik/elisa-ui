#pragma once

#include <gtk/gtk.h>
#include <stdint.h>

GtkWidget *elisa_gtk_accessible_entry_new(int32_t secure);
void elisa_gtk_accessible_entry_set_sensitive(GtkWidget *widget,
                                              int32_t accessibility_sensitive);
