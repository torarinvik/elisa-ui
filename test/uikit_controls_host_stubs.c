/* Host stand-ins for the UIKit native-controls shim.
 *
 * Every entry point records what it was asked to do and hands back a distinct
 * handle, so the realization -- which control each widget kind becomes, where
 * it is attached, what text and state it carries, and the order handles are
 * released in -- can be asserted on macOS with no device.
 */

#include <stddef.h>
#include <stdint.h>

#define ELISA_UIKIT_CONTROLS_MAX 64

static size_t next_handle = 1;

/* One record per created control, in creation order. */
static int created_kind[ELISA_UIKIT_CONTROLS_MAX];   /* see the tokens below */
static int created_selectable[ELISA_UIKIT_CONTROLS_MAX];
static size_t created_handle[ELISA_UIKIT_CONTROLS_MAX];
static size_t created_parent[ELISA_UIKIT_CONTROLS_MAX];
static float created_x[ELISA_UIKIT_CONTROLS_MAX];
static float created_y[ELISA_UIKIT_CONTROLS_MAX];
static float created_width[ELISA_UIKIT_CONTROLS_MAX];
static float created_height[ELISA_UIKIT_CONTROLS_MAX];
static int created_has_title[ELISA_UIKIT_CONTROLS_MAX];
static int created_has_label_text[ELISA_UIKIT_CONTROLS_MAX];
static int created_has_field_text[ELISA_UIKIT_CONTROLS_MAX];
static int created_has_accessibility_label[ELISA_UIKIT_CONTROLS_MAX];
static int created_selected[ELISA_UIKIT_CONTROLS_MAX];
static float created_progress[ELISA_UIKIT_CONTROLS_MAX];
static float created_content_width[ELISA_UIKIT_CONTROLS_MAX];
static int created_count = 0;

static size_t released_order[ELISA_UIKIT_CONTROLS_MAX];
static int released_count = 0;

enum {
    ElisaStubView = 1,
    ElisaStubScroll = 2,
    ElisaStubLabel = 3,
    ElisaStubButton = 4,
    ElisaStubField = 5,
    ElisaStubSlider = 6,
    ElisaStubProgress = 7,
};

void elisa_uikit_controls_stub_reset(void) {
    created_count = 0;
    released_count = 0;
    next_handle = 1;
}

int elisa_uikit_controls_stub_count(void) { return created_count; }
int elisa_uikit_controls_stub_released_count(void) { return released_count; }

static int slot_of(size_t handle) {
    for (int index = 0; index < created_count; index += 1) {
        if (created_handle[index] == handle) return index;
    }
    return -1;
}

/* Test-facing queries, by creation order. */
int elisa_uikit_controls_stub_kind(int slot) {
    return slot < 0 || slot >= created_count ? 0 : created_kind[slot];
}
int elisa_uikit_controls_stub_selectable(int slot) {
    return slot < 0 || slot >= created_count ? -1 : created_selectable[slot];
}
size_t elisa_uikit_controls_stub_parent(int slot) {
    return slot < 0 || slot >= created_count ? 0 : created_parent[slot];
}
size_t elisa_uikit_controls_stub_handle(int slot) {
    return slot < 0 || slot >= created_count ? 0 : created_handle[slot];
}
float elisa_uikit_controls_stub_width(int slot) {
    return slot < 0 || slot >= created_count ? -1.0f : created_width[slot];
}
float elisa_uikit_controls_stub_height(int slot) {
    return slot < 0 || slot >= created_count ? -1.0f : created_height[slot];
}
int elisa_uikit_controls_stub_has_title(int slot) {
    return slot < 0 || slot >= created_count ? 0 : created_has_title[slot];
}
int elisa_uikit_controls_stub_has_label_text(int slot) {
    return slot < 0 || slot >= created_count ? 0 : created_has_label_text[slot];
}
int elisa_uikit_controls_stub_has_field_text(int slot) {
    return slot < 0 || slot >= created_count ? 0 : created_has_field_text[slot];
}
int elisa_uikit_controls_stub_has_accessibility_label(int slot) {
    return slot < 0 || slot >= created_count ? 0 : created_has_accessibility_label[slot];
}
int elisa_uikit_controls_stub_selected(int slot) {
    return slot < 0 || slot >= created_count ? -1 : created_selected[slot];
}
float elisa_uikit_controls_stub_progress(int slot) {
    return slot < 0 || slot >= created_count ? -1.0f : created_progress[slot];
}
float elisa_uikit_controls_stub_content_width(int slot) {
    return slot < 0 || slot >= created_count ? -1.0f : created_content_width[slot];
}
size_t elisa_uikit_controls_stub_released(int order) {
    return order < 0 || order >= released_count ? 0 : released_order[order];
}

static size_t create(int kind, int selectable) {
    if (created_count >= ELISA_UIKIT_CONTROLS_MAX) return 0;
    int slot = created_count;
    created_count += 1;
    created_kind[slot] = kind;
    created_selectable[slot] = selectable;
    created_handle[slot] = next_handle;
    next_handle += 1;
    created_parent[slot] = 0;
    created_x[slot] = 0.0f;
    created_y[slot] = 0.0f;
    created_width[slot] = 0.0f;
    created_height[slot] = 0.0f;
    created_has_title[slot] = 0;
    created_has_label_text[slot] = 0;
    created_has_field_text[slot] = 0;
    created_has_accessibility_label[slot] = 0;
    created_selected[slot] = -1;
    created_progress[slot] = -1.0f;
    created_content_width[slot] = -1.0f;
    return created_handle[slot];
}

int elisa_uikit_controls_run(void) { return 0; }
size_t elisa_uikit_controls_create_view(void) { return create(ElisaStubView, -1); }
size_t elisa_uikit_controls_create_scroll_view(int vertical, int horizontal) {
    (void)vertical; (void)horizontal;
    return create(ElisaStubScroll, -1);
}
size_t elisa_uikit_controls_create_label(void) { return create(ElisaStubLabel, -1); }
size_t elisa_uikit_controls_create_button(int selectable) { return create(ElisaStubButton, selectable); }
size_t elisa_uikit_controls_create_text_field(void) { return create(ElisaStubField, -1); }
size_t elisa_uikit_controls_create_slider(float low, float high, float value) {
    (void)low; (void)high; (void)value;
    return create(ElisaStubSlider, -1);
}
size_t elisa_uikit_controls_create_progress(void) { return create(ElisaStubProgress, -1); }

void elisa_uikit_controls_release(size_t handle) {
    if (handle == 0 || released_count >= ELISA_UIKIT_CONTROLS_MAX) return;
    released_order[released_count] = handle;
    released_count += 1;
}

void elisa_uikit_controls_add_child(size_t parent, size_t child) {
    int slot = slot_of(child);
    if (slot < 0) return;
    created_parent[slot] = parent;
}

void elisa_uikit_controls_set_frame(size_t handle, float x, float y, float width, float height) {
    int slot = slot_of(handle);
    if (slot < 0) return;
    created_x[slot] = x;
    created_y[slot] = y;
    created_width[slot] = width;
    created_height[slot] = height;
}

void elisa_uikit_controls_set_content_size(size_t handle, float width, float height) {
    int slot = slot_of(handle);
    (void)height;
    if (slot >= 0) created_content_width[slot] = width;
}

void elisa_uikit_controls_set_label_text(size_t handle, size_t text) {
    int slot = slot_of(handle);
    if (slot >= 0 && text != 0) created_has_label_text[slot] = 1;
}
void elisa_uikit_controls_set_button_title(size_t handle, size_t text) {
    int slot = slot_of(handle);
    if (slot >= 0 && text != 0) created_has_title[slot] = 1;
}
void elisa_uikit_controls_set_field_text(size_t handle, size_t text) {
    int slot = slot_of(handle);
    if (slot >= 0 && text != 0) created_has_field_text[slot] = 1;
}
void elisa_uikit_controls_set_accessibility_label(size_t handle, size_t text) {
    int slot = slot_of(handle);
    if (slot >= 0 && text != 0) created_has_accessibility_label[slot] = 1;
}
void elisa_uikit_controls_set_button_selected(size_t handle, int selected) {
    int slot = slot_of(handle);
    if (slot >= 0) created_selected[slot] = selected;
}
void elisa_uikit_controls_set_slider_state(size_t handle, float low, float high, float value) {
    (void)handle; (void)low; (void)high; (void)value;
}
void elisa_uikit_controls_set_progress(size_t handle, float fraction) {
    int slot = slot_of(handle);
    if (slot >= 0) created_progress[slot] = fraction;
}
