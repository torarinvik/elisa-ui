/* elisa-ui: the C boundary.
 *
 * C has no sum type, so an event crosses as a flat record whose `kind` is the
 * published wire ordinal. The Elisa side keeps the sealed hierarchy; these are
 * one conversion each way over it, so adding a kind to the hierarchy reaches C
 * without either side learning about the other.
 *
 * TWO DIRECTIONS, and a program uses one or both:
 *
 *   A C HOST driving an Elisa app links src/capi/ui_capi.elisa and calls
 *   elisa_ui_dispatch_event / elisa_ui_set_viewport.
 *
 *   A C APP driven by a native backend links src/capi/ui_capi_app.elisa and
 *   IMPLEMENTS the elisa_ui_on_* callbacks below. That file supplies the Elisa
 *   app contract and forwards to them, so a C app never sees an Elisa type.
 */
#ifndef ELISA_UI_H
#define ELISA_UI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

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
    ELISA_UI_EVENT_GAMEPAD_AXIS   = 11
} elisa_ui_event_kind;

/* Mirrors UiCore::EventRecord field for field.
 *
 * Which fields carry meaning depends on `kind`, and only on `kind`:
 *   POINTER_*, SCROLL   x, y  = position
 *   SCROLL              dx, dy = wheel delta
 *   POINTER_DOWN/UP     code  = button
 *   KEY_*               code  = key, in GLFW's numbering (see UiCore::Key)
 *   RESIZE              x, y  = width, height
 *   GAMEPAD_BUTTON/AXIS dx    = value, code = button or axis
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
 * which an app ignores, rather than as a trap. */
void elisa_ui_dispatch_event(int32_t kind, float x, float y,
                             float dx, float dy, int32_t code);

void  elisa_ui_set_viewport(float width, float height);
float elisa_ui_viewport_width(void);
float elisa_ui_viewport_height(void);

/* ---- A C app driven by a backend (src/capi/ui_capi_app.elisa) ---- */

/* Implement these. ui_capi_app.elisa supplies the Elisa app contract and
 * forwards to them, flattening each event on the way. */
void elisa_ui_on_init(void);
void elisa_ui_on_event(const elisa_ui_event *event);
void elisa_ui_on_frame(void);
void elisa_ui_on_widget_event(size_t widget, int32_t event);

#ifdef __cplusplus
}
#endif

#endif /* ELISA_UI_H */
