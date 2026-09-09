// The Elisa side of the custom AppKit bridge, as the bridge test sees it: every callback
// appkit_canvas_shim.m declares `extern` is defined here against scripted state, so the
// shim can be driven without the framework and its decisions observed.
//
// Not a translation unit of its own: appkit_canvas_bridge_test.m includes this file after
// the shim and before main(). The `test_*` statics ARE the assertions' subject -- main
// reads them directly, which is why they stay file-scope rather than behind accessors.

#import <Cocoa/Cocoa.h>

static float test_slider_value = 0.25f;
static char test_text[128] = "Hello";
static size_t test_selection_start = 5;
static size_t test_selection_end = 5;
static size_t test_marked_start;
static size_t test_marked_end;
static int test_undo_calls;
static int test_redo_calls;
static int test_text_selector;
static int test_click_count;
static int test_click_button;
static int test_pointer_kind;
static int test_pointer_button;
static size_t test_input_window;
static size_t test_cursor_window;
static int test_window_focused = -1;
static size_t test_focus_window;
static size_t test_environment_window;
static size_t test_resize_window;
static size_t test_frame_window;
static NSUInteger test_frame_count;
static int test_allows_readback = 1;
static int test_text_focused = 1;
static int test_allow_text_mutation = 1;
static int test_tooltip_calls;
static size_t test_timer_fired_window;
static uint32_t test_timer_fired_generation;
static size_t test_timer_fired_handle;
static size_t test_closed_window;
static int test_invalid_attributed_substring;
static int test_invalid_attributed_substring_released;
static size_t test_accessibility_handles[3];
static size_t test_window_handle;
static size_t test_native_text_bytes(size_t native, char *buffer, size_t capacity);

@interface ElisaInvalidAttributedSubstring : NSObject
@end
@implementation ElisaInvalidAttributedSubstring
- (void)dealloc {
    test_invalid_attributed_substring_released = 1;
}
@end

void elisa_appkit_canvas_insert_text(const char *bytes, size_t length);

static size_t test_accessibility_float_value(float value) {
    return (size_t)(void *)CFNumberCreate(NULL, kCFNumberFloat32Type, &value);
}

void elisa_appkit_canvas_frame(size_t windowHandle, size_t context) {
    (void)context;
    test_frame_window = windowHandle;
    test_frame_count += 1;
    elisa_appkit_canvas_accessibility_reset(test_window_handle);
    size_t sliderElement = elisa_appkit_canvas_accessibility_add(test_window_handle, test_accessibility_handles[0], test_accessibility_handles[0] == 0, (size_t)(__bridge void *)@"elisa-ui-7", (size_t)(__bridge void *)NSAccessibilitySliderRole, 0,
        (size_t)(__bridge void *)@"Intensity", (size_t)(__bridge void *)@"Adjust preview intensity",
        10, 10, 180, 24, 1, 0);
    elisa_appkit_canvas_accessibility_add_tooltip(test_window_handle, sliderElement, 10, 10, 180, 24);
    size_t sliderValue = test_accessibility_float_value(test_slider_value);
    size_t sliderMinimum = test_accessibility_float_value(0.0f);
    size_t sliderMaximum = test_accessibility_float_value(1.0f);
    elisa_appkit_canvas_accessibility_set_range_values(sliderElement, sliderValue, sliderMinimum, sliderMaximum);
    if (sliderValue != 0) CFRelease((CFTypeRef)(void *)sliderValue);
    if (sliderMinimum != 0) CFRelease((CFTypeRef)(void *)sliderMinimum);
    if (sliderMaximum != 0) CFRelease((CFTypeRef)(void *)sliderMaximum);
    size_t textElement = elisa_appkit_canvas_accessibility_add(test_window_handle, test_accessibility_handles[1], test_accessibility_handles[1] == 0, (size_t)(__bridge void *)@"elisa-ui-8", (size_t)(__bridge void *)NSAccessibilityTextFieldRole, 0,
        (size_t)(__bridge void *)@"Project name", (size_t)(__bridge void *)@"Edit the project name",
        10, 44, 180, 32, 1, test_text_focused);
    elisa_appkit_canvas_accessibility_add_tooltip(test_window_handle, textElement, 10, 44, 180, 32);
    NSString *textValue = [NSString stringWithUTF8String:test_text];
    NSString *selectedValue = [[NSString alloc]
        initWithBytes:test_text + test_selection_start
               length:test_selection_end - test_selection_start encoding:NSUTF8StringEncoding];
    elisa_appkit_canvas_accessibility_set_text(textElement, (size_t)(__bridge void *)textValue,
        (size_t)(__bridge void *)selectedValue,
        elisa_appkit_canvas_selection_location(test_window_handle), elisa_appkit_canvas_selection_length(test_window_handle));
    const char *masked = "••••";
    size_t secureElement = elisa_appkit_canvas_accessibility_add(test_window_handle, test_accessibility_handles[2], test_accessibility_handles[2] == 0, (size_t)(__bridge void *)@"elisa-ui-9", (size_t)(__bridge void *)NSAccessibilityTextFieldRole, (size_t)(__bridge void *)NSAccessibilitySecureTextFieldSubrole,
        (size_t)(__bridge void *)@"Password", (size_t)(__bridge void *)@"Secure entry",
        10, 80, 180, 32, 1, 0);
    elisa_appkit_canvas_accessibility_add_tooltip(test_window_handle, secureElement, 10, 80, 180, 32);
    elisa_appkit_canvas_accessibility_set_text(secureElement, (size_t)(__bridge void *)[NSString stringWithUTF8String:masked],
        (size_t)(__bridge void *)@"", 0, 0);
    test_accessibility_handles[0] = sliderElement;
    test_accessibility_handles[1] = textElement;
    test_accessibility_handles[2] = secureElement;
    CFArrayRef children = CFArrayCreate(NULL,
                                        (const void **)(const void *)test_accessibility_handles,
                                        3, NULL);
    elisa_appkit_canvas_accessibility_commit(test_window_handle, (size_t)(void *)children);
    CFRelease(children);
}

// The production bitmap path is implemented by Elisa through CoreGraphics and
// ImageIO. This bridge-only callback keeps the shim test focused on its FFI
// trampoline while preserving the old status/error assertions.
int elisa_appkit_canvas_render_headless(size_t windowHandle, size_t snapshot,
                                        int pixelsWidth, int pixelsHeight) {
    if (windowHandle == 0 || windowHandle != test_window_handle ||
        pixelsWidth <= 0 || pixelsHeight <= 0) return 0;
    if (snapshot != 0) {
        id object = (__bridge id)(void *)snapshot;
        if (![object isKindOfClass:[NSString class]]) return 0;
        NSString *directory = [(NSString *)object stringByDeletingLastPathComponent];
        if (![[NSFileManager defaultManager] fileExistsAtPath:directory]) return 0;
    }
    elisa_appkit_canvas_frame(test_window_handle, 0);
    return 1;
}

void elisa_appkit_canvas_resize(size_t windowHandle, float width, float height) {
    test_resize_window = windowHandle;
    (void)width; (void)height;
}
void elisa_appkit_canvas_pointer_move(float x, float y) {
    (void)x; (void)y;
    test_pointer_kind = 0;
    test_pointer_button = 0;
}
void elisa_appkit_canvas_pointer_down(float x, float y, int button) {
    (void)x; (void)y;
    test_pointer_kind = 1;
    test_pointer_button = button;
}
void elisa_appkit_canvas_pointer_up(float x, float y, int button) {
    (void)x; (void)y;
    test_pointer_kind = 2;
    test_pointer_button = button;
}
void elisa_appkit_canvas_pointer_leave(void) {
    test_pointer_kind = 3;
    test_pointer_button = 0;
}
size_t elisa_appkit_canvas_pointer_leave_event(size_t windowHandle) {
    test_input_window = windowHandle;
    elisa_appkit_canvas_pointer_leave();
    return (size_t)(__bridge void *)[NSCursor arrowCursor];
}
void elisa_appkit_canvas_pointer_scroll(size_t windowHandle, float x, float y, float dx, float dy) {
    test_input_window = windowHandle;
    (void)x; (void)y; (void)dx; (void)dy;
    test_pointer_kind = 4;
    test_pointer_button = 0;
}
void elisa_appkit_canvas_key_down_event(size_t windowHandle, size_t event, int keyCode, size_t character, size_t modifiers) {
    test_input_window = windowHandle;
    (void)event; (void)keyCode; (void)character; (void)modifiers;
}
void elisa_appkit_canvas_key_up(size_t windowHandle, int keyCode, size_t character) {
    test_input_window = windowHandle;
    (void)keyCode; (void)character;
}
void elisa_appkit_canvas_raw_flags(size_t windowHandle, int keyCode, size_t modifiers) {
    test_input_window = windowHandle;
    (void)keyCode; (void)modifiers;
}
size_t elisa_appkit_canvas_accessibility_capacity(void) { return 256; }
void elisa_appkit_canvas_focus_changed(size_t windowHandle, int focused) {
    test_focus_window = windowHandle;
    test_window_focused = focused;
}
void elisa_appkit_canvas_accessibility_environment_changed(size_t windowHandle) {
    test_environment_window = windowHandle;
}
void elisa_appkit_canvas_timer_fired(size_t windowHandle, uint32_t generation, size_t timerHandle) {
    test_timer_fired_window = windowHandle;
    test_timer_fired_generation = generation;
    test_timer_fired_handle = timerHandle;
}
int elisa_appkit_canvas_key_down_route(int character, size_t modifiers) {
    BOOL shift = (modifiers & NSEventModifierFlagShift) != 0;
    BOOL superKey = (modifiers & NSEventModifierFlagCommand) != 0;
    if (!superKey) return test_text_focused ? 1 : 0;
    if (character == 'a') return 2;
    if (character == 'c') return 3;
    if (character == 'x') return 4;
    if (character == 'v') return 5;
    if (character == 'z') return shift ? 7 : 6;
    return 0;
}
static size_t test_accessibility_index_for_handle(size_t handle) {
    if (handle == test_accessibility_handles[0]) return 7;
    if (handle == test_accessibility_handles[1]) return 8;
    if (handle == test_accessibility_handles[2]) return 9;
    return elisa_appkit_canvas_not_found;
}
int elisa_appkit_canvas_accessibility_activate(size_t windowHandle, size_t handle) {
    test_input_window = windowHandle;
    return test_accessibility_index_for_handle(handle) == 7;
}
size_t elisa_appkit_canvas_accessibility_tooltip_text(size_t windowHandle, size_t handle) {
    test_input_window = windowHandle;
    if (handle == 0) return 0;
    id object = (__bridge id)(void *)handle;
    if (![object isKindOfClass:[ElisaAccessibilityElement class]]) return 0;
    test_tooltip_calls += 1;
    return (size_t)CFBridgingRetain(@"tooltip supplied by Elisa");
}
int elisa_appkit_canvas_accessibility_increment_direction(void) { return 1; }
int elisa_appkit_canvas_accessibility_decrement_direction(void) { return -1; }
int elisa_appkit_canvas_accessibility_adjust(size_t windowHandle, size_t handle, int direction) {
    test_input_window = windowHandle;
    if (test_accessibility_index_for_handle(handle) != 7) return 0;
    test_slider_value += direction > 0 ? 0.05f : -0.05f;
    return 1;
}
size_t elisa_appkit_canvas_accessibility_set_value(size_t windowHandle, size_t handle, size_t value) {
    test_input_window = windowHandle;
    id object = value == 0 ? nil : (__bridge id)(void *)value;
    if (test_accessibility_index_for_handle(handle) == 7 &&
        [object isKindOfClass:[NSNumber class]]) {
        float scalar = [(NSNumber *)object floatValue];
        test_slider_value = scalar < 0.0f ? 0.0f : (scalar > 1.0f ? 1.0f : scalar);
        return (size_t)(void *)CFNumberCreate(NULL, kCFNumberFloat32Type, &test_slider_value);
    }
    if (test_accessibility_index_for_handle(handle) == 8 &&
        [object isKindOfClass:[NSString class]] && test_allow_text_mutation) {
        size_t take = test_native_text_bytes(value, test_text, sizeof(test_text) - 1);
        test_text[take] = '\0';
        test_selection_start = test_selection_end = take;
        return (size_t)CFRetain((CFTypeRef)object);
    }
    return 0;
}
void elisa_appkit_canvas_window_closed(size_t windowHandle) { test_closed_window = windowHandle; }
void elisa_appkit_canvas_rebuild_cursor_rects(size_t windowHandle) { test_cursor_window = windowHandle; }
int elisa_appkit_canvas_view_is_flipped(void) { return 1; }
int elisa_appkit_canvas_view_accepts_first_responder(void) { return 1; }
int elisa_appkit_canvas_view_is_accessibility_element(void) { return 0; }
size_t elisa_appkit_canvas_tracking_options(void) {
    return NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited |
           NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect;
}
int elisa_appkit_canvas_allows_text_readback(void) { return test_allows_readback; }
int elisa_appkit_canvas_text_action_enabled(int action) {
    if (action == 5 || action == 6) return 1;
    if (action == 2 || action == 3) {
        return test_allows_readback && test_selection_end > test_selection_start;
    }
    if (action == 4) {
        return [[NSPasteboard generalPasteboard]
            availableTypeFromArray:@[NSPasteboardTypeString]] != nil;
    }
    return action == 1;
}
int elisa_appkit_canvas_text_action_valid(int action) {
    return action == 0 || elisa_appkit_canvas_text_action_enabled(action);
}
int elisa_appkit_canvas_perform_text_action(int action) {
    if (!elisa_appkit_canvas_text_action_enabled(action)) return 0;
    if (action == 1) {
        test_selection_start = 0;
        test_selection_end = strlen(test_text);
        return 1;
    }
    if (action == 2 || action == 3) {
        size_t length = test_selection_end - test_selection_start;
        NSString *selected = [[NSString alloc]
            initWithBytes:test_text + test_selection_start
                   length:length encoding:NSUTF8StringEncoding];
        if (selected == nil || !elisa_appkit_canvas_clipboard_write(
                (size_t)(__bridge void *)selected,
                (size_t)(__bridge void *)NSPasteboardTypeString)) return 0;
        if (action == 3) elisa_appkit_canvas_insert_text("", 0);
        return action == 3;
    }
    if (action == 4) {
        size_t nativeText = elisa_appkit_canvas_clipboard_read(
            (size_t)(__bridge void *)NSPasteboardTypeString);
        if (nativeText == 0) return 0;
        NSString *clipboardText = (__bridge NSString *)(void *)nativeText;
        NSData *utf8 = [clipboardText dataUsingEncoding:NSUTF8StringEncoding];
        unsigned char buffer[sizeof(test_text)];
        size_t length = MIN((size_t)utf8.length, sizeof(buffer));
        if (length > 0) memcpy(buffer, utf8.bytes, length);
        CFRelease((CFTypeRef)(void *)nativeText);
        if (length == 0) return 0;
        elisa_appkit_canvas_insert_text((const char *)buffer, length);
        return 1;
    }
    if (action == 5) { test_undo_calls += 1; return 1; }
    if (action == 6) { test_redo_calls += 1; return 1; }
    return 0;
}
size_t elisa_appkit_canvas_cursor_at(float x, float y) {
    (void)x; (void)y;
    return (size_t)(__bridge void *)[NSCursor IBeamCursor];
}
size_t elisa_appkit_canvas_pointer_move_event(size_t windowHandle, float x, float y) {
    test_input_window = windowHandle;
    elisa_appkit_canvas_pointer_move(x, y);
    return elisa_appkit_canvas_cursor_at(x, y);
}
size_t elisa_appkit_canvas_cursor_leave(void) {
    return (size_t)(__bridge void *)[NSCursor arrowCursor];
}
void elisa_appkit_canvas_text_click(float x, int button, int clickCount) {
    (void)x;
    test_click_button = button;
    test_click_count = clickCount;
}
void elisa_appkit_canvas_pointer_button(size_t windowHandle, float x, float y, int button, int down, int clickCount) {
    test_input_window = windowHandle;
    if (down) {
        elisa_appkit_canvas_pointer_down(x, y, button);
        elisa_appkit_canvas_text_click(x, button, clickCount);
        return;
    }
    elisa_appkit_canvas_pointer_up(x, y, button);
}
void elisa_appkit_canvas_insert_text(const char *bytes, size_t length) {
    size_t used = strlen(test_text);
    size_t start = MIN(test_selection_start, used);
    size_t stop = MIN(test_selection_end, used);
    size_t take = MIN(length, sizeof(test_text) - (used - (stop - start)) - 1);
    memmove(test_text + start + take, test_text + stop, used - stop + 1);
    if (take > 0) memcpy(test_text + start, bytes, take);
    test_selection_start = test_selection_end = start + take;
}
static size_t test_native_text_bytes(size_t native, char *buffer, size_t capacity) {
    if (native == 0) return 0;
    id object = (__bridge id)(void *)native;
    NSString *value = [object isKindOfClass:[NSAttributedString class]]
        ? [(NSAttributedString *)object string]
        : ([object isKindOfClass:[NSString class]] ? (NSString *)object : nil);
    if (value == nil) return 0;
    NSData *utf8 = [value dataUsingEncoding:NSUTF8StringEncoding];
    size_t take = MIN((size_t)utf8.length, capacity);
    if (take > 0) memcpy(buffer, utf8.bytes, take);
    return take;
}
static NSUInteger test_utf16_from_byte(size_t byteOffset) {
    NSString *prefix = [[NSString alloc] initWithBytes:test_text length:MIN(byteOffset, strlen(test_text)) encoding:NSUTF8StringEncoding];
    return prefix.length;
}
static size_t test_byte_from_utf16(NSUInteger offset) {
    NSString *value = [NSString stringWithUTF8String:test_text];
    NSUInteger safe = MIN(offset, value.length);
    return [[value substringToIndex:safe] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
}
size_t elisa_appkit_canvas_selection_location(size_t windowHandle) {
    test_input_window = windowHandle;
    return test_utf16_from_byte(test_selection_start);
}
size_t elisa_appkit_canvas_selection_length(size_t windowHandle) {
    test_input_window = windowHandle;
    return test_utf16_from_byte(test_selection_end) - test_utf16_from_byte(test_selection_start);
}
static int test_set_selected_range_index(size_t index, size_t location, size_t length) {
    if (index != 8 || !test_allow_text_mutation) return 0;
    test_selection_start = test_byte_from_utf16(location);
    test_selection_end = test_byte_from_utf16(location + length);
    return 1;
}
int elisa_appkit_canvas_set_selected_range(size_t windowHandle, size_t handle, size_t location, size_t length) {
    test_input_window = windowHandle;
    if (test_accessibility_index_for_handle(handle) != 8) return 0;
    return test_set_selected_range_index(8, location, length);
}
int elisa_appkit_canvas_selected_range(size_t windowHandle, size_t handle,
                                       size_t *actualLocation, size_t *actualLength) {
    test_input_window = windowHandle;
    if (test_accessibility_index_for_handle(handle) != 8 ||
        actualLocation == NULL || actualLength == NULL) return 0;
    *actualLocation = elisa_appkit_canvas_selection_location(windowHandle);
    *actualLength = elisa_appkit_canvas_selection_length(windowHandle);
    return 1;
}
size_t elisa_appkit_canvas_marked_location(size_t windowHandle) {
    test_input_window = windowHandle;
    return test_marked_end > test_marked_start ? test_utf16_from_byte(test_marked_start) : NSNotFound;
}
size_t elisa_appkit_canvas_marked_length(size_t windowHandle) {
    test_input_window = windowHandle;
    return test_utf16_from_byte(test_marked_end) - test_utf16_from_byte(test_marked_start);
}
int elisa_appkit_canvas_has_marked_text(size_t windowHandle) {
    test_input_window = windowHandle;
    return test_marked_end > test_marked_start;
}
void elisa_appkit_canvas_commit_text(size_t windowHandle, size_t native, size_t replacementLocation, size_t replacementLength) {
    test_input_window = windowHandle;
    char bytes[sizeof(test_text)];
    size_t length = test_native_text_bytes(native, bytes, sizeof(bytes));
    if (replacementLocation != NSNotFound) test_set_selected_range_index(8, replacementLocation, replacementLength);
    else if (test_marked_end > test_marked_start) {
        test_selection_start = test_marked_start;
        test_selection_end = test_marked_end;
    }
    elisa_appkit_canvas_insert_text(bytes, length);
    test_marked_start = test_marked_end = 0;
}
void elisa_appkit_canvas_update_marked_text(size_t windowHandle, size_t native, size_t selectedLocation, size_t selectedLength, size_t replacementLocation, size_t replacementLength) {
    test_input_window = windowHandle;
    char bytes[sizeof(test_text)];
    size_t length = test_native_text_bytes(native, bytes, sizeof(bytes));
    if (replacementLocation != NSNotFound) test_set_selected_range_index(8, replacementLocation, replacementLength);
    else if (test_marked_end > test_marked_start) {
        test_selection_start = test_marked_start;
        test_selection_end = test_marked_end;
    }
    size_t start = test_selection_start;
    elisa_appkit_canvas_insert_text(bytes, length);
    test_marked_start = start;
    test_marked_end = test_selection_end;
    NSString *marked = [[NSString alloc] initWithBytes:test_text + start length:test_marked_end - start encoding:NSUTF8StringEncoding];
    NSUInteger relativeStart = MIN(selectedLocation, marked.length);
    NSUInteger relativeEnd = MIN(selectedLocation + selectedLength, marked.length);
    test_selection_start = start + [[marked substringToIndex:relativeStart] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    test_selection_end = start + [[marked substringToIndex:relativeEnd] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
}
void elisa_appkit_canvas_unmark_text(size_t windowHandle) {
    test_input_window = windowHandle;
    test_marked_start = test_marked_end = 0;
}
size_t elisa_appkit_canvas_valid_marked_attributes(size_t windowHandle) {
    test_input_window = windowHandle;
    CFArrayRef value = CFArrayCreate(NULL, NULL, 0, NULL);
    return (size_t)(void *)value;
}
static int test_selector_token(const char *name) {
    if (strcmp(name, "moveLeft:") == 0) return 1;
    if (strcmp(name, "moveRight:") == 0) return 2;
    if (strcmp(name, "moveLeftAndModifySelection:") == 0) return 3;
    if (strcmp(name, "moveRightAndModifySelection:") == 0) return 4;
    if (strcmp(name, "moveWordRightAndModifySelection:") == 0) return 17;
    if (strcmp(name, "deleteWordBackward:") == 0) return 18;
    return 0;
}
void elisa_appkit_canvas_text_selector(const char *selectorName) { test_text_selector = test_selector_token(selectorName); }
int elisa_appkit_canvas_text_action(const char *selectorName) {
    if (strcmp(selectorName, "selectAll:") == 0) return 1;
    if (strcmp(selectorName, "copy:") == 0) return 2;
    if (strcmp(selectorName, "cut:") == 0) return 3;
    if (strcmp(selectorName, "paste:") == 0) return 4;
    if (strcmp(selectorName, "undo:") == 0) return 5;
    if (strcmp(selectorName, "redo:") == 0) return 6;
    return 0;
}
void elisa_appkit_canvas_text_selector_handle(size_t windowHandle, size_t selector) {
    test_input_window = windowHandle;
    if (selector == 0) return;
    elisa_appkit_canvas_text_selector(sel_getName((SEL)(void *)selector));
}
int elisa_appkit_canvas_text_action_handle(size_t selector) {
    if (selector == 0) return 0;
    return elisa_appkit_canvas_text_action(sel_getName((SEL)(void *)selector));
}
void elisa_appkit_canvas_text_action_selector(size_t windowHandle, size_t selector) {
    test_input_window = windowHandle;
    int action = elisa_appkit_canvas_text_action_handle(selector);
    if (action != 0) (void)elisa_appkit_canvas_perform_text_action(action);
}
int elisa_appkit_canvas_text_action_valid_selector(size_t windowHandle, size_t selector) {
    test_input_window = windowHandle;
    int action = elisa_appkit_canvas_text_action_handle(selector);
    return elisa_appkit_canvas_text_action_valid(action);
}
float elisa_appkit_canvas_character_x(size_t location) { return 10.0f + (float)location * 5.0f; }
float elisa_appkit_canvas_caret_width(void) { return 1.0f; }
float elisa_appkit_canvas_caret_y(void) { return 50.0f; }
float elisa_appkit_canvas_caret_height(void) { return 16.0f; }
size_t elisa_appkit_canvas_character_at_x(size_t windowHandle, float x) {
    test_input_window = windowHandle;
    if (!test_text_focused) return NSNotFound;
    return x < 40.0f ? 0 : [NSString stringWithUTF8String:test_text].length;
}
static size_t test_range_location(size_t location) {
    return MIN(location, [NSString stringWithUTF8String:test_text].length);
}
static size_t test_range_length(size_t location, size_t length) {
    size_t safeLocation = test_range_location(location);
    size_t remaining = [NSString stringWithUTF8String:test_text].length - safeLocation;
    return MIN(length, remaining);
}
size_t elisa_appkit_canvas_attributed_substring(size_t windowHandle, size_t location, size_t length,
                                               size_t *actualLocation, size_t *actualLength) {
    test_input_window = windowHandle;
    if (!test_text_focused || !test_allows_readback || location == NSNotFound) return 0;
    if (test_invalid_attributed_substring) {
        ElisaInvalidAttributedSubstring *invalid = [ElisaInvalidAttributedSubstring new];
        return (size_t)CFBridgingRetain(invalid);
    }
    if (actualLocation != NULL) *actualLocation = test_range_location(location);
    if (actualLength != NULL) *actualLength = test_range_length(location, length);
    NSString *value = [NSString stringWithUTF8String:test_text];
    NSUInteger safeLocation = test_range_location(location);
    NSUInteger safeLength = test_range_length(location, length);
    NSString *substring = [value substringWithRange:NSMakeRange(safeLocation, safeLength)];
    NSAttributedString *attributed = [[NSAttributedString alloc] initWithString:substring];
    return (size_t)CFBridgingRetain(attributed);
}
int elisa_appkit_canvas_first_rect(size_t windowHandle, size_t location, size_t length,
                                   size_t *actualLocation, size_t *actualLength,
                                   float *x, float *y, float *width, float *height) {
    test_input_window = windowHandle;
    if (!test_text_focused) return 0;
    if (actualLocation != NULL) *actualLocation = test_range_location(location);
    if (actualLength != NULL) *actualLength = test_range_length(location, length);
    if (x != NULL) *x = elisa_appkit_canvas_character_x(actualLocation == NULL ? location : *actualLocation);
    if (y != NULL) *y = elisa_appkit_canvas_caret_y();
    if (width != NULL) *width = elisa_appkit_canvas_caret_width();
    if (height != NULL) *height = elisa_appkit_canvas_caret_height();
    return 1;
}
