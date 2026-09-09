/* Host stand-ins for the UIKit shim's C entry points.
 *
 * The UIKit backend's policy -- input routing, semantics, surface facts and
 * the whole CoreGraphics/CoreText paint path -- is platform-neutral Apple
 * code. These stubs let all of it run and be asserted on macOS, where there is
 * no UIApplication to enter, so the backend has a real gate that needs neither
 * a device nor a simulator. The Objective-C shim is checked separately by
 * compiling it against the iOS SDK.
 *
 * The accessibility stubs hand out distinct, releasable handles so the
 * identity and reuse policy in Elisa is exercised, not bypassed.
 */

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

const size_t elisa_uikit_not_found = (size_t)-1;

static size_t elisa_uikit_stub_view = 0;
static size_t elisa_uikit_stub_children = 0;
static int elisa_uikit_stub_live_elements = 0;

/* Test-facing controls. Declared in the Elisa test as externs. */
void elisa_uikit_stub_set_view(size_t handle) { elisa_uikit_stub_view = handle; }
size_t elisa_uikit_stub_committed_children(void) { return elisa_uikit_stub_children; }
int elisa_uikit_stub_live_element_count(void) { return elisa_uikit_stub_live_elements; }

int elisa_uikit_run(void) { return 0; }
void elisa_uikit_stop(void) {}
size_t elisa_uikit_view_handle(void) { return elisa_uikit_stub_view; }
void elisa_uikit_redraw(size_t viewHandle) { (void)viewHandle; }
size_t elisa_uikit_schedule_redraw(float delay, size_t viewHandle, uint32_t generation) {
    (void)delay; (void)viewHandle; (void)generation;
    return 0;
}
void elisa_uikit_cancel_redraw(size_t handle) { (void)handle; }
void elisa_uikit_set_status_bar_hidden(int hidden) { (void)hidden; }
void elisa_uikit_set_idle_timer_disabled(int disabled) { (void)disabled; }

int elisa_uikit_begin_text_input(size_t viewHandle) { (void)viewHandle; return 1; }
int elisa_uikit_end_text_input(size_t viewHandle) { (void)viewHandle; return 1; }
void elisa_uikit_reload_input_views(size_t viewHandle) { (void)viewHandle; }

int elisa_uikit_clipboard_write(size_t text) { (void)text; return 0; }
size_t elisa_uikit_clipboard_read(void) { return 0; }

size_t elisa_uikit_accessibility_add(size_t viewHandle, size_t previousHandle, int isNew,
                                     size_t identifier, uint64_t traits,
                                     size_t label, size_t hint, size_t value,
                                     float x, float y, float width, float height, int enabled) {
    (void)viewHandle; (void)identifier; (void)traits; (void)label; (void)hint; (void)value;
    (void)x; (void)y; (void)width; (void)height; (void)enabled;
    if (isNew == 0 && previousHandle != 0) return previousHandle;
    void *element = malloc(1);
    if (element == NULL) return 0;
    elisa_uikit_stub_live_elements += 1;
    return (size_t)element;
}

int elisa_uikit_accessibility_update(size_t viewHandle, size_t handle,
                                     size_t identifier, uint64_t traits,
                                     size_t label, size_t hint, size_t value,
                                     float x, float y, float width, float height, int enabled) {
    (void)viewHandle; (void)identifier; (void)traits; (void)label; (void)hint; (void)value;
    (void)x; (void)y; (void)width; (void)height; (void)enabled;
    return handle != 0;
}

void elisa_uikit_accessibility_release(size_t handle) {
    if (handle == 0) return;
    elisa_uikit_stub_live_elements -= 1;
    free((void *)handle);
}

int elisa_uikit_accessibility_commit(size_t viewHandle, size_t children) {
    (void)viewHandle;
    if (children == 0) return 0;
    elisa_uikit_stub_children = children;
    return 1;
}

void elisa_uikit_accessibility_post_layout_changed(size_t viewHandle) { (void)viewHandle; }
static size_t elisa_uikit_stub_focused = 0;
size_t elisa_uikit_stub_focused_element(void) { return elisa_uikit_stub_focused; }
void elisa_uikit_accessibility_focus(size_t viewHandle, size_t handle) {
    (void)viewHandle;
    elisa_uikit_stub_focused = handle;
}
void elisa_uikit_accessibility_post_screen_changed(size_t viewHandle) { (void)viewHandle; }
