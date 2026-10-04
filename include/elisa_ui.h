/* elisa-ui: the C boundary.
 *
 * C has no sum type, so an event crosses as a flat record whose `kind` is the
 * published wire ordinal. The Elisa side keeps the sealed hierarchy; these are
 * one conversion each way over it, so adding a kind to the hierarchy reaches C
 * without either side learning about the other.
 *
 * TWO DIRECTIONS, and a program uses one or both:
 *
 *   A C HOST driving an Elisa app links src/capi/ui_capi.elisa, checks
 *   elisa_ui_abi_version(), then calls elisa_ui_dispatch_event /
 *   elisa_ui_set_viewport.
 *
 *   A C APP driven by a native backend links src/capi/ui_capi_app.elisa and
 *   IMPLEMENTS the elisa_ui_on_* callbacks below. That file supplies the Elisa
 *   app contract and forwards to them, so a C app never sees an Elisa type or
 *   retained-arena index.
 */
#ifndef ELISA_UI_H
#define ELISA_UI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Packed as 0xMMmmpp (major, minor, patch). The version is returned by Elisa's
 * boundary implementation before any host events are sent. A major mismatch
 * is incompatible; minor/patch changes preserve the existing wire records. */
#define ELISA_UI_ABI_VERSION_MAJOR 1u
#define ELISA_UI_ABI_VERSION_MINOR 1u
#define ELISA_UI_ABI_VERSION_PATCH 0u
#define ELISA_UI_ABI_VERSION \
    ((ELISA_UI_ABI_VERSION_MAJOR << 16) | \
     (ELISA_UI_ABI_VERSION_MINOR << 8) | ELISA_UI_ABI_VERSION_PATCH)

/* Maximum bytes staged for one committed-text or IME dispatch. */
#define ELISA_UI_MAX_TEXT_BYTES 1024u

uint32_t elisa_ui_abi_version(void);

/* THREADING AND CALLBACKS: except for the pure ABI-version query above, this
 * boundary is single-threaded and does not marshal or synchronize calls. The
 * host must serialize every stateful elisa_ui_* call on one UI-owner thread;
 * elisa_ui_on_* callbacks run synchronously on that same thread. Post worker
 * completions to the UI thread before calling back into the framework. Event
 * dispatch from inside an app callback is queued; nested text dispatch is
 * ignored while Elisa's borrowed-text staging buffer is in use. */

/* Wire ordinals. Stable: they are what crosses this boundary and the
 * wasmbrowser one, and UiCore::wire_kind is exhaustive over them, so a kind
 * added without a number here is a compile error on the Elisa side. */
typedef enum {
    ELISA_UI_EVENT_NONE           = 0,
    ELISA_UI_EVENT_QUIT           = 1,
    ELISA_UI_EVENT_POINTER_MOVE   = 2,
    ELISA_UI_EVENT_POINTER_DOWN   = 3,
    ELISA_UI_EVENT_POINTER_UP     = 4,
    ELISA_UI_EVENT_POINTER_LEAVE  = 5,
    ELISA_UI_EVENT_KEY_DOWN       = 6,
    ELISA_UI_EVENT_KEY_UP         = 7,
    ELISA_UI_EVENT_RESIZE         = 8,
    ELISA_UI_EVENT_SCROLL         = 9,
    ELISA_UI_EVENT_GAMEPAD_BUTTON = 10,
    ELISA_UI_EVENT_GAMEPAD_AXIS   = 11,
    ELISA_UI_EVENT_FOCUS_GAINED   = 12,
    ELISA_UI_EVENT_FOCUS_LOST     = 13,
    ELISA_UI_EVENT_POINTER_CANCEL = 14,
    ELISA_UI_EVENT_CONTACT_BEGAN = 15,
    ELISA_UI_EVENT_CONTACT_MOVED = 16,
    ELISA_UI_EVENT_CONTACT_ENDED = 17,
    ELISA_UI_EVENT_CONTACT_CANCELLED = 18
} elisa_ui_event_kind;

typedef enum {
    ELISA_UI_CONTACT_FINGER = 0,
    ELISA_UI_CONTACT_STYLUS = 1,
    ELISA_UI_CONTACT_INDIRECT = 2,
    ELISA_UI_CONTACT_UNKNOWN = 3
} elisa_ui_contact_tool;

/* Mirrors UiCore::EventRecord field for field.
 *
 * Which fields carry meaning depends on `kind`, and only on `kind`:
 *   POINTER_*, SCROLL   x, y  = position
 *   SCROLL              dx, dy = wheel delta
 *   POINTER_DOWN/UP     code  = button (0 primary, 1 secondary, 2 middle,
 *                                      3 back, 4 forward)
 *   KEY_*               code  = key, in GLFW's numbering (see UiCore::Key)
 *   RESIZE              x, y  = width, height
 *   GAMEPAD_BUTTON/AXIS dx    = value, code = button or axis
 *   FOCUS_GAINED/LOST   no payload
 *   POINTER_CANCEL     no payload; release capture without activation
 *   CONTACT_*          x, y = position; dx = monotonic seconds, dy = tool;
 *                      code = uint32_t contact identity bits
 * Everything else is zero. */
typedef struct {
    int32_t kind;
    float   x;
    float   y;
    float   dx;
    float   dy;
    int32_t code;
} elisa_ui_event;

/* ---- A C host driving an Elisa app (src/capi/ui_capi.elisa) ---- */

/* Deliver one event. An ordinal the library does not model arrives as NONE,
 * which an app ignores, rather than as a trap. If an application callback
 * dispatches another event, it is queued for the current drain instead of
 * recursively entering the callback. */
void elisa_ui_dispatch_event(int32_t kind, float x, float y,
                             float dx, float dy, int32_t code);
/* Deliver committed UTF-8 text. The pointer is borrowed for the duration of
 * the call; a null pointer paired with a non-zero length is ignored. The
 * counted payload may contain U+0000; use `length`, not `strlen`, when reading
 * it. Lengths above ELISA_UI_MAX_TEXT_BYTES are clipped to that byte budget,
 * while a length that cannot fit the signed view extent is ignored. A nested
 * dispatch from the callback is ignored while the single Elisa-owned staging
 * buffer is borrowed by the outer call. */
void elisa_ui_dispatch_text_input(const char *text, size_t length);
/* Deliver live IME composition text. The pointer is borrowed for the duration
 * of the call; selection offsets are UTF-8 scalar positions inside the
 * bounded payload and are clamped before the Elisa callback is reached. */
void elisa_ui_dispatch_text_editing(const char *text, size_t length,
                                    int32_t selected_start,
                                    int32_t selected_length);

void  elisa_ui_set_viewport(float width, float height);
float elisa_ui_viewport_width(void);
float elisa_ui_viewport_height(void);

/* ---- A C app driven by a backend (src/capi/ui_capi_app.elisa) ---- */

/* Implement these. ui_capi_app.elisa supplies the Elisa app contract and
 * forwards to them, flattening each event on the way. */
void elisa_ui_on_init(void);
void elisa_ui_on_event(const elisa_ui_event *event);
/* Committed UTF-8 text is variable-length and intentionally separate from the
 * fixed-size key event record. The pointer is borrowed for this callback. */
void elisa_ui_on_text_input(const char *text, size_t length);
/* Live IME composition. Selection offsets are Unicode-scalar counts inside
 * text, matching SDL's portable text-editing contract. */
void elisa_ui_on_text_editing(const char *text, size_t length,
                              int32_t selected_start, int32_t selected_length);
void elisa_ui_on_frame(void);
/* Opaque retained-widget identity. The token is valid only for the current
 * retained tree lifetime; zero means that the target was invalid or no longer
 * addressable. Store and compare it as an opaque value. Do not decode its
 * representation or persist it across a tree reset/rebuild. */
typedef uint64_t elisa_ui_widget_handle;
#define ELISA_UI_WIDGET_HANDLE_INVALID UINT64_C(0)
void elisa_ui_on_widget_event(elisa_ui_widget_handle widget, int32_t event);

/* ---- A C app constructing retained controls through opaque handles ---- */

/* Rebuild the complete retained tree. All widget handles issued before this
 * call become invalid. Parent handle zero is the root-parent sentinel. */
#define ELISA_UI_WIDGET_ROOT_PARENT UINT64_C(0)
void elisa_ui_widget_tree_reset(void);
/* Colors are packed as 0xRRGGBBAA. Builders return zero on failure. */
elisa_ui_widget_handle elisa_ui_widget_column(elisa_ui_widget_handle parent,
                                              float padding, float spacing,
                                              uint32_t color_rgba);
elisa_ui_widget_handle elisa_ui_widget_row(elisa_ui_widget_handle parent,
                                           float padding, float spacing,
                                           uint32_t color_rgba);
elisa_ui_widget_handle elisa_ui_widget_label(elisa_ui_widget_handle parent,
                                              const char *text, size_t length,
                                              float size, uint32_t color_rgba);
/* Create an editable field with an initial counted UTF-8 value. Label and
 * placeholder decoration can be composed from sibling labels. */
elisa_ui_widget_handle elisa_ui_widget_text_field(elisa_ui_widget_handle parent,
                                                  const char *initial, size_t length,
                                                  float min_width, float min_height,
                                                  float size, uint32_t ink_rgba,
                                                  uint32_t fill_rgba);
elisa_ui_widget_handle elisa_ui_widget_button(elisa_ui_widget_handle parent,
                                              float min_width, float min_height,
                                              uint32_t color_rgba,
                                              uint32_t hover_rgba,
                                              uint32_t press_rgba);
elisa_ui_widget_handle elisa_ui_widget_radio_button(elisa_ui_widget_handle parent,
                                                    float min_width, float min_height,
                                                    uint32_t color_rgba,
                                                    uint32_t hover_rgba,
                                                    uint32_t press_rgba);
elisa_ui_widget_handle elisa_ui_widget_check_box(elisa_ui_widget_handle parent,
                                                 float min_width, float min_height,
                                                 uint32_t color_rgba,
                                                 uint32_t hover_rgba,
                                                 uint32_t press_rgba);
elisa_ui_widget_handle elisa_ui_widget_slider(elisa_ui_widget_handle parent,
                                              float min_width, float min_height,
                                              float value, uint32_t track_rgba,
                                              uint32_t fill_rgba, uint32_t thumb_rgba);
elisa_ui_widget_handle elisa_ui_widget_progress_bar(elisa_ui_widget_handle parent,
                                                     float min_width, float min_height,
                                                     float value, uint32_t track_rgba,
                                                     uint32_t fill_rgba);
/* Counted UTF-8 is clipped to ELISA_UI_MAX_TEXT_BYTES and to a valid prefix.
 * Setters return 1 for a live handle and accepted operation, 0 otherwise. */
int32_t elisa_ui_widget_set_text(elisa_ui_widget_handle widget,
                                 const char *text, size_t length,
                                 float size, uint32_t color_rgba);
int32_t elisa_ui_widget_set_enabled(elisa_ui_widget_handle widget,
                                    int32_t enabled);
int32_t elisa_ui_widget_set_visible(elisa_ui_widget_handle widget,
                                    int32_t visible);
/* Selection applies to radio buttons and check boxes; radio-group policy is
 * owned by the application. Values apply to sliders and progress bars and
 * are finite, normalized to [0, 1]. A query returns 0 for false/unsupported
 * or stale selection; value returns 0 for unsupported/stale handles. */
int32_t elisa_ui_widget_set_selected(elisa_ui_widget_handle widget,
                                     int32_t selected);
int32_t elisa_ui_widget_selected(elisa_ui_widget_handle widget);
int32_t elisa_ui_widget_set_value(elisa_ui_widget_handle widget, float value);
float elisa_ui_widget_value(elisa_ui_widget_handle widget);
/* Text-field length is -1 for stale/non-text handles. Copy writes at most
 * capacity bytes without a terminator and never splits a UTF-8 sequence;
 * pass NULL only with zero capacity. Request-focus is text-field-only. */
int32_t elisa_ui_widget_request_text_focus(elisa_ui_widget_handle widget);
int32_t elisa_ui_widget_text_length(elisa_ui_widget_handle widget);
size_t elisa_ui_widget_copy_text(elisa_ui_widget_handle widget,
                                 char *destination, size_t capacity);
int32_t elisa_ui_widget_activate(elisa_ui_widget_handle widget);
int32_t elisa_ui_widget_is_valid(elisa_ui_widget_handle widget);

#ifdef __cplusplus
}
#endif

#endif /* ELISA_UI_H */
