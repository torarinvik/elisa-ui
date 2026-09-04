// Runtime checks for the custom AppKit bridge. The implementation is included
// into this translation unit deliberately: its retained semantic objects are
// private production state, and identity stability is the behavior under test.

#import "../src/platform/appkit/appkit_canvas_shim.m"

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
static int test_window_focused = -1;
static int test_allows_readback = 1;
static int test_text_focused = 1;

void elisa_appkit_canvas_insert_text(const char *bytes, size_t length);

void elisa_appkit_canvas_frame(size_t context) {
    (void)context;
    elisa_appkit_canvas_accessibility_reset();
    const char *label = "Intensity";
    const char *help = "Adjust preview intensity";
    elisa_appkit_canvas_accessibility_add(7, "elisa-ui-7", 10, 7, NSAccessibilitySliderRole, 0,
        (size_t)(__bridge void *)[NSCursor pointingHandCursor],
        label, strlen(label), help, strlen(help), 10, 10, 180, 24, 1, 0);
    elisa_appkit_canvas_accessibility_add_tooltip(7);
    elisa_appkit_canvas_accessibility_set_range(7, test_slider_value, 0.0f, 1.0f);
    elisa_appkit_canvas_accessibility_add(8, "elisa-ui-8", 10, 8, NSAccessibilityTextFieldRole, 0,
        (size_t)(__bridge void *)[NSCursor IBeamCursor],
        "Project name", 12, "Edit the project name", 21,
        10, 44, 180, 32, 1, test_text_focused);
    elisa_appkit_canvas_accessibility_add_tooltip(8);
    elisa_appkit_canvas_accessibility_set_text(8, test_text, strlen(test_text),
        test_text + test_selection_start, test_selection_end - test_selection_start,
        elisa_appkit_canvas_selection_location(), elisa_appkit_canvas_selection_length());
    const char *masked = "••••";
    elisa_appkit_canvas_accessibility_add(9, "elisa-ui-9", 10, 9, NSAccessibilityTextFieldRole, NSAccessibilitySecureTextFieldSubrole,
        (size_t)(__bridge void *)[NSCursor IBeamCursor],
        "Password", 8, "Secure entry", 12, 10, 80, 180, 32, 1, 0);
    elisa_appkit_canvas_accessibility_add_tooltip(9);
    elisa_appkit_canvas_accessibility_set_text(9, masked, strlen(masked), "", 0, 0, 0);
    elisa_appkit_canvas_accessibility_commit();
    elisa_appkit_canvas_accessibility_post_layout_changed(
        elisa_appkit_canvas_accessibility_layout_changed_notification());
}

void elisa_appkit_canvas_resize(float width, float height) { (void)width; (void)height; }
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
void elisa_appkit_canvas_pointer_scroll(float x, float y, float dx, float dy) {
    (void)x; (void)y; (void)dx; (void)dy;
    test_pointer_kind = 4;
    test_pointer_button = 0;
}
void elisa_appkit_canvas_raw_key(int down, int keyCode, int character) { (void)down; (void)keyCode; (void)character; }
void elisa_appkit_canvas_key_down_event(size_t event, int keyCode, int character, size_t modifiers) {
    (void)event; (void)keyCode; (void)character; (void)modifiers;
}
void elisa_appkit_canvas_key_up(int keyCode, int character) { (void)keyCode; (void)character; }
void elisa_appkit_canvas_raw_flags(int keyCode, size_t modifiers) {
    (void)keyCode; (void)modifiers;
}
void elisa_appkit_canvas_focus_changed(int focused) { test_window_focused = focused; }
void elisa_appkit_canvas_accessibility_environment_changed(void) {}
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
int elisa_appkit_canvas_accessibility_activate(size_t index) { (void)index; return 0; }
int elisa_appkit_canvas_accessibility_adjust(size_t index, int direction) {
    if (index != 7) return 0;
    test_slider_value += direction > 0 ? 0.05f : -0.05f;
    return 1;
}
void elisa_appkit_canvas_cancel_interaction(void) {}
int elisa_appkit_canvas_accepts_text(void) { return 1; }
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
int elisa_appkit_canvas_perform_text_action(int action) {
    if (!elisa_appkit_canvas_text_action_enabled(action)) return 0;
    if (action == 1) {
        test_selection_start = 0;
        test_selection_end = strlen(test_text);
        return 1;
    }
    if (action == 2 || action == 3) {
        size_t length = test_selection_end - test_selection_start;
        if (!elisa_appkit_canvas_clipboard_write(
                (const unsigned char *)test_text + test_selection_start, length,
                elisa_appkit_canvas_pasteboard_type_string())) return 0;
        if (action == 3) elisa_appkit_canvas_insert_text("", 0);
        return action == 3;
    }
    if (action == 4) {
        unsigned char buffer[sizeof(test_text)];
        size_t length = elisa_appkit_canvas_clipboard_read(buffer, sizeof(buffer),
                                                           elisa_appkit_canvas_pasteboard_type_string());
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
size_t elisa_appkit_canvas_cursor_leave(void) {
    return (size_t)(__bridge void *)[NSCursor arrowCursor];
}
void elisa_appkit_canvas_text_click(float x, int button, int clickCount) {
    (void)x;
    test_click_button = button;
    test_click_count = clickCount;
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
void elisa_appkit_canvas_set_text(size_t index, const char *bytes, size_t length) {
    if (index != 8) return;
    size_t take = MIN(length, sizeof(test_text) - 1);
    memcpy(test_text, bytes, take);
    test_text[take] = '\0';
    test_selection_start = test_selection_end = take;
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
size_t elisa_appkit_canvas_selection_location(void) { return test_utf16_from_byte(test_selection_start); }
size_t elisa_appkit_canvas_selection_length(void) { return test_utf16_from_byte(test_selection_end) - test_utf16_from_byte(test_selection_start); }
void elisa_appkit_canvas_set_selected_range(size_t index, size_t location, size_t length) {
    if (index != 8) return;
    test_selection_start = test_byte_from_utf16(location);
    test_selection_end = test_byte_from_utf16(location + length);
}
size_t elisa_appkit_canvas_marked_location(void) { return test_utf16_from_byte(test_marked_start); }
size_t elisa_appkit_canvas_marked_length(void) { return test_utf16_from_byte(test_marked_end) - test_utf16_from_byte(test_marked_start); }
void elisa_appkit_canvas_commit_text(const char *bytes, size_t length, size_t replacementLocation, size_t replacementLength, int hasReplacement) {
    if (hasReplacement) elisa_appkit_canvas_set_selected_range(8, replacementLocation, replacementLength);
    else if (test_marked_end > test_marked_start) {
        test_selection_start = test_marked_start;
        test_selection_end = test_marked_end;
    }
    elisa_appkit_canvas_insert_text(bytes, length);
    test_marked_start = test_marked_end = 0;
}
void elisa_appkit_canvas_update_marked_text(const char *bytes, size_t length, size_t selectedLocation, size_t selectedLength, size_t replacementLocation, size_t replacementLength, int hasReplacement) {
    if (hasReplacement) elisa_appkit_canvas_set_selected_range(8, replacementLocation, replacementLength);
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
void elisa_appkit_canvas_unmark_text(void) { test_marked_start = test_marked_end = 0; }
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
float elisa_appkit_canvas_character_x(size_t location) { return 10.0f + (float)location * 5.0f; }
float elisa_appkit_canvas_caret_y(void) { return 50.0f; }
float elisa_appkit_canvas_caret_height(void) { return 16.0f; }
size_t elisa_appkit_canvas_character_at_x(float x) { return x < 40.0f ? 0 : [NSString stringWithUTF8String:test_text].length; }
size_t elisa_appkit_canvas_range_location(size_t location) {
    return MIN(location, [NSString stringWithUTF8String:test_text].length);
}
size_t elisa_appkit_canvas_range_length(size_t location, size_t length) {
    size_t safeLocation = elisa_appkit_canvas_range_location(location);
    size_t remaining = [NSString stringWithUTF8String:test_text].length - safeLocation;
    return MIN(length, remaining);
}
const unsigned char *elisa_appkit_canvas_range_pointer(size_t location) {
    return (const unsigned char *)test_text + test_byte_from_utf16(elisa_appkit_canvas_range_location(location));
}
size_t elisa_appkit_canvas_range_byte_length(size_t location, size_t length) {
    size_t safeLocation = elisa_appkit_canvas_range_location(location);
    size_t safeLength = elisa_appkit_canvas_range_length(location, length);
    return test_byte_from_utf16(safeLocation + safeLength) - test_byte_from_utf16(safeLocation);
}

static int require(BOOL condition, NSString *message) {
    if (condition) return 0;
    fprintf(stderr, "appkit canvas bridge: %s\n", message.UTF8String);
    return 1;
}

int main(void) {
    @autoreleasepool {
        NSString *title = @"test";
        int opened = elisa_appkit_canvas_open((size_t)(__bridge void *)title,
                                              200, 100, 15,
                                              elisa_appkit_canvas_backing_store_buffered(),
                                              NSWindowTabbingModeDisallowed, 0, 1,
                                              NSApplicationActivationPolicyProhibited);
        if (!opened) return 1;
        if (require([elisa_canvas_view isFlipped], @"canvas coordinate policy was not supplied by Elisa")) return 1;
        if (require([elisa_canvas_view acceptsFirstResponder], @"canvas focus policy was not supplied by Elisa")) return 1;
        if (require(![elisa_canvas_view isAccessibilityElement], @"canvas semantic-root policy was not supplied by Elisa")) return 1;
        elisa_appkit_canvas_center();
        elisa_appkit_canvas_menus_begin();
        int applicationMenu = elisa_appkit_canvas_menu_add("test", 4);
        elisa_appkit_canvas_menu_add_item(applicationMenu, "About test", 10, "orderFrontStandardAboutPanel:", 0, 0);
        elisa_appkit_canvas_menu_add_separator(applicationMenu);
        elisa_appkit_canvas_menu_add_item(applicationMenu, "Quit test", 9, "terminate:", 'q', NSEventModifierFlagCommand);
        int windowMenu = elisa_appkit_canvas_menu_add("Window", 6);
        elisa_appkit_canvas_menu_set_windows(windowMenu);
        elisa_appkit_canvas_menu_add_item(windowMenu, "Minimize", 8, "performMiniaturize:", 'm', NSEventModifierFlagCommand);
        elisa_appkit_canvas_menus_commit();
        if (require(NSApp.mainMenu.numberOfItems == 2, @"declarative menu roots missing")) return 1;
        NSMenu *applicationSubmenu = [NSApp.mainMenu itemAtIndex:0].submenu;
        if (require([[applicationSubmenu itemAtIndex:0].title isEqualToString:@"About test"], @"application-name menu expansion failed")) return 1;
        if (require([applicationSubmenu itemAtIndex:2].action == @selector(terminate:), @"menu action token mapped incorrectly")) return 1;
        if (require([[applicationSubmenu itemAtIndex:2].keyEquivalent isEqualToString:@"q"], @"menu key equivalent mapped incorrectly")) return 1;
        if (require([applicationSubmenu itemAtIndex:2].keyEquivalentModifierMask == NSEventModifierFlagCommand, @"native menu modifier mask was not preserved")) return 1;
        if (require(NSApp.windowsMenu == [NSApp.mainMenu itemAtIndex:1].submenu, @"window menu designation failed")) return 1;
        if (require(elisa_appkit_canvas_present_headless(
                        elisa_appkit_canvas_bitmap_color_space_calibrated_rgb(),
                        elisa_appkit_canvas_bitmap_file_type_png(), "", 0), @"off-screen presentation failed")) return 1;
        if (require(elisa_canvas_frame_count > 0, @"off-screen frame did not draw")) return 1;
        NSNotification *focusNotification = [NSNotification notificationWithName:NSWindowDidResignKeyNotification object:elisa_canvas_window];
        [elisa_canvas_delegate windowDidResignKey:focusNotification];
        if (require(test_window_focused == 0, @"window focus loss did not reach Elisa")) return 1;
        [elisa_canvas_delegate windowDidBecomeKey:focusNotification];
        if (require(test_window_focused == 1, @"window focus gain did not reach Elisa")) return 1;
        if (require(!elisa_appkit_canvas_present_headless(
                         elisa_appkit_canvas_bitmap_color_space_calibrated_rgb(),
                         elisa_appkit_canvas_bitmap_file_type_png(),
                         "/elisa-ui-missing-directory/frame.png",
                         strlen("/elisa-ui-missing-directory/frame.png")), @"snapshot failure did not cross the FFI boundary")) return 1;
        NSEvent *singleClick = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
            location:NSMakePoint(40, 20) modifierFlags:0 timestamp:0
            windowNumber:elisa_canvas_window.windowNumber context:nil eventNumber:1
            clickCount:1 pressure:1.0];
        [elisa_canvas_view mouseDown:singleClick];
        if (require(test_click_button == 0 && test_click_count == 1, @"single click facts did not reach Elisa")) return 1;
        NSEvent *doubleClick = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
            location:NSMakePoint(40, 20) modifierFlags:0 timestamp:0
            windowNumber:elisa_canvas_window.windowNumber context:nil eventNumber:2
            clickCount:2 pressure:1.0];
        [elisa_canvas_view mouseDown:doubleClick];
        if (require(test_click_button == 0 && test_click_count == 2, @"native click facts did not reach Elisa")) return 1;
        NSEvent *rightClick = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown
            location:NSMakePoint(40, 20) modifierFlags:0 timestamp:0
            windowNumber:elisa_canvas_window.windowNumber context:nil eventNumber:3
            clickCount:2 pressure:1.0];
        [elisa_canvas_view rightMouseDown:rightClick];
        if (require(test_pointer_kind == 1 && test_pointer_button == 1,
                    @"right-button press did not cross the pointer FFI")) return 1;
        if (require(test_click_button == 1 && test_click_count == 2,
                    @"right-button click facts did not reach Elisa")) return 1;
        NSEvent *rightRelease = [NSEvent mouseEventWithType:NSEventTypeRightMouseUp
            location:NSMakePoint(40, 20) modifierFlags:0 timestamp:0
            windowNumber:elisa_canvas_window.windowNumber context:nil eventNumber:4
            clickCount:2 pressure:0.0];
        [elisa_canvas_view rightMouseUp:rightRelease];
        if (require(test_pointer_kind == 2 && test_pointer_button == 1,
                    @"right-button release did not cross the pointer FFI")) return 1;
        if (require(elisa_accessibility_children.count == 3, @"semantic children missing")) return 1;

        ElisaAccessibilityElement *first = elisa_accessibility_children[0];
        if (require([first.accessibilityRole isEqualToString:NSAccessibilitySliderRole], @"wrong slider role")) return 1;
        if (require([first.accessibilityIdentifier isEqualToString:@"elisa-ui-7"], @"accessibility identifier did not cross the FFI")) return 1;
        if (require(first.elisaCursor == [NSCursor pointingHandCursor], @"opaque cursor pointer was not installed")) return 1;
        if (require([first.accessibilityHelp isEqualToString:@"Adjust preview intensity"], @"help text missing")) return 1;
        if (require(fabs([first.accessibilityValue floatValue] - 0.25f) < 0.001f, @"wrong initial value")) return 1;
        ElisaAccessibilityElement *textField = elisa_accessibility_children[1];
        if (require([textField.accessibilityRole isEqualToString:NSAccessibilityTextFieldRole], @"wrong text-field role")) return 1;
        if (require([textField.accessibilityValue isEqualToString:@"Hello"], @"wrong editable value")) return 1;
        ElisaAccessibilityElement *secureField = elisa_accessibility_children[2];
        if (require([secureField.accessibilityRole isEqualToString:NSAccessibilityTextFieldRole], @"wrong secure-field role")) return 1;
        if (require([secureField.accessibilitySubrole isEqualToString:NSAccessibilitySecureTextFieldSubrole], @"secure-field subrole missing")) return 1;
        if (require([secureField.accessibilityValue isEqualToString:@"••••"], @"secure accessibility value was not masked")) return 1;
        textField.accessibilityValue = @"World";
        if (require(strcmp(test_text, "World") == 0, @"writable accessibility value did not reach the app")) return 1;
        textField.accessibilitySelectedTextRange = NSMakeRange(1, 3);
        if (require(test_selection_start == 1 && test_selection_end == 4, @"writable accessibility selection did not reach Elisa")) return 1;
        textField.accessibilitySelectedTextRange = NSMakeRange(5, 0);
        [elisa_canvas_view insertText:@"é" replacementRange:NSMakeRange(NSNotFound, 0)];
        if (require(strcmp(test_text, "Worldé") == 0, @"Unicode text commit did not reach the app")) return 1;
        if (require(NSEqualRanges(elisa_canvas_view.selectedRange, NSMakeRange(6, 0)), @"UTF-8 caret did not convert to UTF-16")) return 1;
        NSRange actualRange = NSMakeRange(NSNotFound, 0);
        NSAttributedString *substring = [elisa_canvas_view attributedSubstringForProposedRange:NSMakeRange(5, 1) actualRange:&actualRange];
        if (require([substring.string isEqualToString:@"é"] && NSEqualRanges(actualRange, NSMakeRange(5, 1)), @"Unicode substring did not come from Elisa range slicing")) return 1;
        test_allows_readback = 0;
        if (require([elisa_canvas_view attributedSubstringForProposedRange:NSMakeRange(0, 1) actualRange:NULL] == nil, @"secure substring readback was not denied")) return 1;
        strcpy(test_text, "secret");
        test_selection_start = 0;
        test_selection_end = 6;
        [elisa_canvas_view cut:nil];
        if (require(strcmp(test_text, "secret") == 0, @"disabled secure Cut destroyed text without exporting it")) return 1;
        test_allows_readback = 1;
        strcpy(test_text, "Worldé");

        [elisa_canvas_view selectAll:nil];
        if (require(NSEqualRanges(elisa_canvas_view.selectedRange, NSMakeRange(0, 6)), @"Select All did not cover the field")) return 1;
        [elisa_canvas_view copy:nil];
        if (require([[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:@"Worldé"], @"Copy did not write selected Unicode text")) return 1;
        if (require(elisa_appkit_canvas_clipboard_write(
                        (const unsigned char *)"", 0,
                        elisa_appkit_canvas_pasteboard_type_string()), @"empty clipboard write failed")) return 1;
        if (require([[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:@""], @"empty clipboard write did not clear the pasteboard")) return 1;
        [elisa_canvas_view insertText:@"Next" replacementRange:NSMakeRange(NSNotFound, 0)];
        if (require(strcmp(test_text, "Next") == 0, @"typing did not replace the selection")) return 1;

        strcpy(test_text, "Cafe");
        test_selection_start = test_selection_end = 4;
        [elisa_canvas_view setMarkedText:@"é" selectedRange:NSMakeRange(1, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
        if (require(strcmp(test_text, "Cafeé") == 0, @"marked text was not inserted")) return 1;
        if (require(NSEqualRanges(elisa_canvas_view.markedRange, NSMakeRange(4, 1)), @"marked range is wrong")) return 1;
        if (require(test_marked_start == 4 && test_marked_end == 6, @"marked range did not convert to UTF-8 bytes")) return 1;
        [elisa_canvas_view setMarkedText:@"ø" selectedRange:NSMakeRange(1, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
        if (require(strcmp(test_text, "Cafeø") == 0, @"marked text update did not replace its range")) return 1;
        [elisa_canvas_view insertText:@"å" replacementRange:NSMakeRange(NSNotFound, 0)];
        if (require(strcmp(test_text, "Cafeå") == 0, @"committed text did not replace marked text")) return 1;
        if (require(!elisa_canvas_view.hasMarkedText, @"marked range survived commit")) return 1;
        if (require(test_marked_start == 0 && test_marked_end == 0, @"painted marked range survived commit")) return 1;
        [elisa_canvas_view undo:nil];
        [elisa_canvas_view redo:nil];
        if (require(test_undo_calls == 1 && test_redo_calls == 1, @"Undo/Redo actions did not cross the FFI boundary")) return 1;
        [elisa_canvas_view doCommandBySelector:@selector(moveLeftAndModifySelection:)];
        if (require(test_text_selector == 3, @"native text selector identity did not cross the FFI boundary")) return 1;
        [elisa_canvas_view doCommandBySelector:@selector(moveWordRightAndModifySelection:)];
        if (require(test_text_selector == 17, @"native word-selection identity did not cross the FFI boundary")) return 1;
        [elisa_canvas_view doCommandBySelector:@selector(deleteWordBackward:)];
        if (require(test_text_selector == 18, @"native word-deletion identity did not cross the FFI boundary")) return 1;

        test_slider_value = 0.75f;
        test_text_focused = 0;
        test_selection_start = test_selection_end = 0;
        if (require(elisa_appkit_canvas_present_headless(
                        elisa_appkit_canvas_bitmap_color_space_calibrated_rgb(),
                        elisa_appkit_canvas_bitmap_file_type_png(), "", 0), @"second off-screen presentation failed")) return 1;
        ElisaAccessibilityElement *second = elisa_accessibility_children[0];
        ElisaAccessibilityElement *secondTextField = elisa_accessibility_children[1];
        ElisaAccessibilityElement *secondSecureField = elisa_accessibility_children[2];
        if (require(first == second, @"semantic identity changed across frames")) return 1;
        if (require(textField == secondTextField, @"text-field identity changed across frames")) return 1;
        if (require(secureField == secondSecureField, @"secure-field identity changed across frames")) return 1;
        if (require(fabs([second.accessibilityValue floatValue] - 0.75f) < 0.001f, @"value did not update")) return 1;
        if (require([secondTextField.accessibilitySelectedText isEqualToString:@""] && NSEqualRanges(secondTextField.accessibilitySelectedTextRange, NSMakeRange(0, 0)), @"blurred text field retained stale accessibility selection")) return 1;

        if (require([second accessibilityPerformIncrement], @"increment action was rejected")) return 1;
        if (require(fabs(test_slider_value - 0.80f) < 0.001f, @"increment action did not reach the app")) return 1;
        [elisa_canvas_window close];
    }
    puts("appkit canvas bridge: all checks passed");
    return 0;
}
