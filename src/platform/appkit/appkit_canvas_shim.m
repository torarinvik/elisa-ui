// AppKit host for elisa-ui's CUSTOM-PAINTED backend.
//
// AppKit owns the window, event queue and CoreGraphics context. Elisa owns the
// widget tree and emits UiCore::Command values; drawRect calls back into Elisa
// to replay that command batch into the current context.
//
// The unit is split into fragments under canvas_shim/, #imported below in dependency
// order: forward declarations and the Elisa callback prototypes stay here, and every
// fragment sees them. They are fragments, not translation units -- one compilation
// unit keeps the helpers `static` and the retained Cocoa objects private, which is what
// test/appkit_canvas_bridge_test.m relies on when it includes this file whole. Compile
// only this file; never add a fragment to a build line.

#import <Cocoa/Cocoa.h>
#include <stdint.h>
#include "../../../include/elisa_appkit_skia.h"

extern void elisa_appkit_canvas_frame(size_t windowHandle, size_t context);
#if defined(ELISA_UI_USE_SKIA)
// The Skia build profile links the real compositor from appkit_skia_host.cpp.
// Its shared header is the source of truth for the floating-point backing
// dimensions; keeping a second prototype here would permit an arm64 ABI
// mismatch between the Objective-C caller and C++ implementation.
#endif
extern void elisa_appkit_canvas_resize(size_t windowHandle, float width, float height);
extern size_t elisa_appkit_canvas_pointer_move_event(size_t windowHandle, float x, float y);
extern void elisa_appkit_canvas_pointer_button(size_t windowHandle, float x, float y, int button, int down, int clickCount);
extern void elisa_appkit_canvas_pointer_scroll(size_t windowHandle, float x, float y, float dx, float dy);
extern void elisa_appkit_canvas_raw_flags(size_t windowHandle, int keyCode, size_t modifiers);
extern void elisa_appkit_canvas_focus_changed(size_t windowHandle, int focused);
extern void elisa_appkit_canvas_accessibility_environment_changed(size_t windowHandle);
extern void elisa_appkit_canvas_appearance_changed(size_t windowHandle, size_t appearanceName,
                                                   int increaseContrast, int reduceMotion);
extern void elisa_appkit_canvas_window_closed(size_t windowHandle);
extern void elisa_appkit_canvas_rebuild_cursor_rects(size_t windowHandle);
extern int elisa_appkit_canvas_render_headless(size_t windowHandle,
                                               size_t snapshot,
                                               int pixelsWidth,
                                               int pixelsHeight);
extern void elisa_appkit_canvas_key_down_event(size_t windowHandle, size_t event, int keyCode, size_t character, size_t modifiers);
extern void elisa_appkit_canvas_key_up(size_t windowHandle, int keyCode, size_t character);
extern int elisa_appkit_canvas_accessibility_activate(size_t windowHandle, size_t handle);
extern int elisa_appkit_canvas_accessibility_adjust(size_t windowHandle, size_t handle, int direction);
extern size_t elisa_appkit_canvas_accessibility_tooltip_text(size_t windowHandle, size_t handle);
extern size_t elisa_appkit_canvas_accessibility_set_value(size_t windowHandle, size_t handle, size_t value);
extern int elisa_appkit_canvas_accessibility_increment_direction(void);
extern int elisa_appkit_canvas_accessibility_decrement_direction(void);
extern const size_t elisa_appkit_canvas_not_found;
extern int elisa_appkit_canvas_has_marked_text(size_t windowHandle);
extern size_t elisa_appkit_canvas_pointer_leave_event(size_t windowHandle);
extern void elisa_appkit_canvas_timer_fired(size_t windowHandle, uint32_t generation, size_t timerHandle);
extern size_t elisa_appkit_canvas_selection_location(size_t windowHandle);
extern size_t elisa_appkit_canvas_selection_length(size_t windowHandle);
extern int elisa_appkit_canvas_set_selected_range(size_t windowHandle, size_t handle, size_t location, size_t length);
extern int elisa_appkit_canvas_selected_range(size_t windowHandle, size_t handle,
                                              size_t *actualLocation, size_t *actualLength);
extern size_t elisa_appkit_canvas_marked_location(size_t windowHandle);
extern size_t elisa_appkit_canvas_marked_length(size_t windowHandle);
extern void elisa_appkit_canvas_commit_text(size_t windowHandle, size_t text,
                                            size_t replacementLocation, size_t replacementLength);
extern void elisa_appkit_canvas_update_marked_text(size_t windowHandle, size_t text,
                                                   size_t selectedLocation, size_t selectedLength,
                                                   size_t replacementLocation, size_t replacementLength);
extern void elisa_appkit_canvas_unmark_text(size_t windowHandle);
extern size_t elisa_appkit_canvas_valid_marked_attributes(size_t windowHandle);
extern void elisa_appkit_canvas_text_selector_handle(size_t windowHandle, size_t selector);
extern void elisa_appkit_canvas_text_action_selector(size_t windowHandle, size_t selector);
extern int elisa_appkit_canvas_text_action_valid_selector(size_t windowHandle, size_t selector);
extern size_t elisa_appkit_canvas_character_at_x(size_t windowHandle, float x);
extern size_t elisa_appkit_canvas_attributed_substring(size_t windowHandle, size_t location, size_t length,
                                                       size_t *actualLocation, size_t *actualLength);
extern int elisa_appkit_canvas_first_rect(size_t windowHandle, size_t location, size_t length,
                                          size_t *actualLocation, size_t *actualLength,
                                          float *x, float *y, float *width, float *height);
extern int elisa_appkit_canvas_view_is_flipped(void);
extern int elisa_appkit_canvas_view_accepts_first_responder(void);
extern int elisa_appkit_canvas_view_is_accessibility_element(void);
extern size_t elisa_appkit_canvas_tracking_options(void);

@class ElisaCanvasView;
@class ElisaAccessibilityElement;
static NSString *elisa_appkit_canvas_string(size_t handle);
static NSNumber *elisa_appkit_canvas_number(size_t handle);
static NSAttributedString *elisa_appkit_canvas_attributed_string(size_t handle);

// Cursor objects are Cocoa singletons. Return opaque, non-owning pointers so
// Elisa can select the native object while this shim only installs it.
size_t elisa_appkit_canvas_arrow_cursor(void) {
    return (size_t)(__bridge void *)[NSCursor arrowCursor];
}

size_t elisa_appkit_canvas_pointing_hand_cursor(void) {
    return (size_t)(__bridge void *)[NSCursor pointingHandCursor];
}

size_t elisa_appkit_canvas_ibeam_cursor(void) {
    return (size_t)(__bridge void *)[NSCursor IBeamCursor];
}

// Fragments, in dependency order (each may use what the earlier ones declare).
#import "canvas_shim/accessibility_element.m"
#import "canvas_shim/handles.m"
#import "canvas_shim/delegate.m"
#import "canvas_shim/view.m"
#import "canvas_shim/window.m"
#import "canvas_shim/accessibility.m"
