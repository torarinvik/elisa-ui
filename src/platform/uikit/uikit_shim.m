// UIKit host for elisa-ui's custom-painted backend.
//
// UIKit owns the application, the window, the event queue and the
// CoreGraphics context. Elisa owns the widget tree and emits UiCore::Command
// values; drawRect: calls back into Elisa to replay that command batch into
// the current context.
//
// The unit is split into fragments under shim/, #imported below in dependency
// order: the Elisa callback prototypes stay here and every fragment sees them.
// They are fragments, not translation units -- one compilation unit keeps the
// helpers `static` and the retained UIKit objects private. Compile only this
// file; never add a fragment to a build line.

#import <UIKit/UIKit.h>
#include <stdint.h>

// Surface and frame.
extern void elisa_uikit_frame(size_t viewHandle, size_t context);
extern int elisa_uikit_surface_ready(size_t viewHandle, float width, float height, float scale,
                                     float safeTop, float safeRight, float safeBottom, float safeLeft);
extern void elisa_uikit_surface_resized(size_t viewHandle, float width, float height, float scale);
extern void elisa_uikit_safe_area_changed(size_t viewHandle, float top, float right, float bottom, float left);
extern void elisa_uikit_keyboard_changed(size_t viewHandle, float bottom, int visible);
extern int elisa_uikit_lifecycle(size_t viewHandle, int signal);
extern void elisa_uikit_timer_fired(size_t viewHandle, uint32_t generation, size_t timerHandle);

// Input.
extern void elisa_uikit_touch(size_t viewHandle, int phase, float x, float y, int tapCount);
extern void elisa_uikit_scroll(size_t viewHandle, float x, float y, float dx, float dy);
extern void elisa_uikit_press(size_t viewHandle, int usage, int64_t flags, int down);
extern void elisa_uikit_hover(size_t viewHandle, float x, float y);
extern void elisa_uikit_hover_ended(size_t viewHandle);
// Returns the cursor token (0 default, 1 an activating control, 2 text), or a
// negative value when no control is under the pointer.
extern int elisa_uikit_pointer_region(size_t viewHandle, float x, float y,
                                      float *regionX, float *regionY,
                                      float *regionWidth, float *regionHeight);

// Text input.
extern int elisa_uikit_wants_keyboard(size_t viewHandle);
extern int elisa_uikit_has_text(size_t viewHandle);
extern void elisa_uikit_insert_text(size_t viewHandle, size_t text);
extern void elisa_uikit_delete_backward(size_t viewHandle);

extern void elisa_uikit_appearance_changed(size_t viewHandle, int dark, int highContrast,
                                           int reducedMotion, float scaledBodyPoints);
extern void elisa_uikit_text_action_selector(size_t viewHandle, size_t selector);
extern int elisa_uikit_text_action_valid_selector(size_t viewHandle, size_t selector);

// UITextInput. Positions and ranges are UTF-16 offsets into the focused field;
// elisa_uikit_not_found is "no such position".
extern size_t elisa_uikit_text_length(size_t viewHandle);
extern size_t elisa_uikit_text_clamp_offset(size_t viewHandle, size_t offset);
extern size_t elisa_uikit_text_offset_position(size_t viewHandle, size_t offset, int64_t delta);
extern size_t elisa_uikit_text_in_range(size_t viewHandle, size_t location, size_t length);
extern void elisa_uikit_text_replace_range(size_t viewHandle, size_t location, size_t length, size_t text);
extern size_t elisa_uikit_text_selection_location(size_t viewHandle);
extern size_t elisa_uikit_text_selection_length(size_t viewHandle);
extern int elisa_uikit_text_set_selection(size_t viewHandle, size_t location, size_t length);
extern int elisa_uikit_text_has_marked(size_t viewHandle);
extern size_t elisa_uikit_text_marked_location(size_t viewHandle);
extern size_t elisa_uikit_text_marked_length(size_t viewHandle);
extern void elisa_uikit_text_set_marked(size_t viewHandle, size_t text,
                                        size_t selectedLocation, size_t selectedLength);
extern void elisa_uikit_text_unmark(size_t viewHandle);
extern int elisa_uikit_text_rect(size_t viewHandle, size_t location, size_t length,
                                 float *x, float *y, float *width, float *height);
extern size_t elisa_uikit_text_offset_at_x(size_t viewHandle, float x);

// Semantics.
extern int elisa_uikit_accessibility_activate(size_t viewHandle, size_t handle);
extern int elisa_uikit_accessibility_adjust(size_t viewHandle, size_t handle, int direction);
extern int elisa_uikit_accessibility_increment_direction(void);
extern int elisa_uikit_accessibility_decrement_direction(void);

// The one sentinel Elisa and UIKit must agree on.
const size_t elisa_uikit_not_found = NSNotFound;

@class ElisaUiKitView;

// Handles cross the boundary as size_t. These two helpers are the only place
// that reinterprets one, so an unchecked bridge cast cannot spread through the
// fragments below.
static ElisaUiKitView *elisa_uikit_view(size_t handle);
static NSString *elisa_uikit_string(size_t handle);

// Fragments, in dependency order (each may use what the earlier ones declare).
#import "shim/accessibility_element.m"
#import "shim/view.m"
#import "shim/text_input.m"
#import "shim/controller.m"
#import "shim/host.m"
