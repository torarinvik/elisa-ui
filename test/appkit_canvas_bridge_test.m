// Runtime checks for the custom AppKit bridge. The implementation is included
// into this translation unit deliberately: its retained semantic objects are
// private production state, and identity stability is the behavior under test.

#import "../src/platform/appkit/appkit_canvas_shim.m"
// The scripted Elisa callbacks the shim calls back into (and the state main asserts on).
#import "appkit_canvas_bridge_stubs.m"

static int require(BOOL condition, NSString *message) {
    if (condition) return 0;
    fprintf(stderr, "appkit canvas bridge: %s\n", message.UTF8String);
    return 1;
}

int main(void) {
    @autoreleasepool {
        if (require(!elisa_appkit_canvas_present(0), @"present succeeded before opening a canvas")) return 1;
        if (require(!elisa_appkit_canvas_render_headless(0, 0, 200, 100),
                    @"headless present succeeded before opening a canvas")) return 1;
        NSObject *invalidTitle = [NSObject new];
        size_t invalidTitleDelegate = 0;
        size_t invalidTitleWindow = elisa_appkit_canvas_open(200, 100, 15,
                                              elisa_appkit_canvas_backing_store_buffered,
                                              &invalidTitleDelegate);
        if (require(invalidTitleWindow != 0,
                    @"window construction rejected a title-independent request")) return 1;
        if (require(!elisa_appkit_canvas_set_title(invalidTitleWindow,
                                                   (size_t)(__bridge void *)invalidTitle),
                    @"invalid window title was accepted")) return 1;
        elisa_appkit_canvas_release_delegate(invalidTitleDelegate);
        elisa_appkit_canvas_release_window(invalidTitleWindow);
        NSString *title = @"test";
        elisa_appkit_canvas_set_activation_policy(NSApplicationActivationPolicyProhibited);
        size_t delegateHandle = 0;
        size_t opened = elisa_appkit_canvas_open(200, 100, 15,
                                                 elisa_appkit_canvas_backing_store_buffered,
                                                 &delegateHandle);
        if (!opened) return 1;
        if (require(elisa_appkit_canvas_set_title(opened, (size_t)(__bridge void *)title),
                    @"valid window title was rejected")) return 1;
        test_window_handle = opened;
        elisa_appkit_canvas_timer_fired(opened, 17, 19);
        if (require(test_timer_fired_window == opened,
                    @"timer callback did not carry the window handle")) return 1;
        if (require(test_timer_fired_generation == 17,
                    @"timer callback did not carry the lifecycle generation")) return 1;
        if (require(test_timer_fired_handle == 19,
                    @"timer callback did not carry the retained timer handle")) return 1;
        elisa_appkit_canvas_set_released_when_closed(opened, 0);
        elisa_appkit_canvas_set_tabbing_mode(opened, NSWindowTabbingModeDisallowed);
        elisa_appkit_canvas_set_restorable(opened, 0);
        if (require([elisa_appkit_canvas_view(opened) isFlipped], @"canvas coordinate policy was not supplied by Elisa")) return 1;
        if (require([elisa_appkit_canvas_view(opened) acceptsFirstResponder], @"canvas focus policy was not supplied by Elisa")) return 1;
        if (require(![elisa_appkit_canvas_view(opened) isAccessibilityElement], @"canvas semantic-root policy was not supplied by Elisa")) return 1;
        [elisa_appkit_canvas_view(opened) setFrameSize:NSMakeSize(180, 90)];
        if (require(test_resize_window == opened,
                    @"canvas resize did not carry its window identity to Elisa")) return 1;
        [elisa_appkit_canvas_view(opened) drawRect:NSMakeRect(0, 0, 180, 90)];
        if (require(test_frame_window == opened,
                    @"canvas frame did not carry its window identity to Elisa")) return 1;
        [elisa_appkit_canvas_view(opened) resetCursorRects];
        if (require(test_cursor_window == opened,
                    @"cursor rebuild did not carry its window identity to Elisa")) return 1;
        NSObject *invalidEvent = [NSObject new];
        elisa_appkit_canvas_interpret_key_event((size_t)(__bridge void *)invalidEvent, opened);
        NSObject *invalidTimer = [NSObject new];
        elisa_appkit_canvas_cancel_redraw((size_t)(__bridge void *)invalidTimer);
        elisa_appkit_canvas_center(opened);
        elisa_appkit_canvas_accessibility_commit(opened, 0);
        NSObject *invalidChildren = [NSObject new];
        elisa_appkit_canvas_accessibility_commit(opened, (size_t)(__bridge void *)invalidChildren);
        size_t oversizedHandles[257] = {0};
        CFArrayRef oversizedChildren = CFArrayCreate(NULL,
                                                     (const void **)(const void *)oversizedHandles,
                                                     elisa_appkit_canvas_accessibility_capacity() + 1, NULL);
        elisa_appkit_canvas_accessibility_commit(opened, (size_t)(void *)oversizedChildren);
        CFRelease(oversizedChildren);
    size_t menuBar = elisa_appkit_canvas_menus_begin();
    NSObject *invalidMenuString = [NSObject new];
    if (require(elisa_appkit_canvas_menu_add(
                    menuBar, (size_t)(__bridge void *)invalidMenuString,
                    (size_t)(__bridge void *)@"") == 0,
                @"invalid menu string was accepted")) return 1;
    NSObject *invalidNativeString = [NSObject new];
    if (require(!elisa_appkit_canvas_schedule_redraw(
                    0.1f, (size_t)(__bridge void *)invalidNativeString, opened, 17),
                @"invalid run-loop mode was accepted")) return 1;
    if (require(!elisa_appkit_canvas_render_headless(opened, 0, 0, 100),
                @"invalid bitmap extent was accepted")) return 1;
    if (require(elisa_appkit_canvas_accessibility_add(
                    opened, 0, 1, 0, (size_t)(__bridge void *)NSAccessibilityButtonRole, 0, 0,
                    (size_t)(__bridge void *)invalidNativeString,
                    0, 0, 10, 10, 1, 0) == 0,
                @"invalid accessibility label was accepted")) return 1;
    if (require(elisa_appkit_canvas_accessibility_add(
                    opened, 0, 1, 0, (size_t)(__bridge void *)invalidNativeString, 0,
                    (size_t)(__bridge void *)@"Label", 0,
                    0, 0, 10, 10, 1, 0) == 0,
                @"invalid accessibility role was accepted")) return 1;
    if (require(elisa_appkit_canvas_accessibility_add(
                    opened, (size_t)(__bridge void *)invalidNativeString, 0, 0,
                    (size_t)(__bridge void *)NSAccessibilityButtonRole, 0,
                    (size_t)(__bridge void *)@"Label", 0,
                    0, 0, 10, 10, 1, 0) == 0,
                @"malformed accessibility reuse handle was accepted")) return 1;
    size_t applicationMenu = elisa_appkit_canvas_menu_add(menuBar, (size_t)(__bridge void *)@"test", (size_t)(__bridge void *)@"");
        elisa_appkit_canvas_menu_add_item(applicationMenu, (size_t)(__bridge void *)@"About test", (size_t)(__bridge void *)@"", (size_t)(void *)sel_registerName("orderFrontStandardAboutPanel:"), 0);
        elisa_appkit_canvas_menu_add_separator(applicationMenu);
        elisa_appkit_canvas_menu_add_item(applicationMenu, (size_t)(__bridge void *)@"Quit test", (size_t)(__bridge void *)@"q", (size_t)(void *)sel_registerName("terminate:"), NSEventModifierFlagCommand);
    size_t windowMenu = elisa_appkit_canvas_menu_add(menuBar, (size_t)(__bridge void *)@"Window", (size_t)(__bridge void *)@"");
        elisa_appkit_canvas_menu_set_windows(windowMenu);
        elisa_appkit_canvas_menu_add_item(windowMenu, (size_t)(__bridge void *)@"Minimize", (size_t)(__bridge void *)@"m", (size_t)(void *)sel_registerName("performMiniaturize:"), NSEventModifierFlagCommand);
    elisa_appkit_canvas_menus_commit(menuBar);
        if (require(NSApp.mainMenu.numberOfItems == 2, @"declarative menu roots missing")) return 1;
        NSMenu *applicationSubmenu = [NSApp.mainMenu itemAtIndex:0].submenu;
        if (require([[applicationSubmenu itemAtIndex:0].title isEqualToString:@"About test"], @"application-name menu expansion failed")) return 1;
        if (require([applicationSubmenu itemAtIndex:2].action == @selector(terminate:), @"menu action token mapped incorrectly")) return 1;
        if (require([[applicationSubmenu itemAtIndex:2].keyEquivalent isEqualToString:@"q"], @"menu key equivalent mapped incorrectly")) return 1;
        if (require([applicationSubmenu itemAtIndex:2].keyEquivalentModifierMask == NSEventModifierFlagCommand, @"native menu modifier mask was not preserved")) return 1;
        if (require(NSApp.windowsMenu == [NSApp.mainMenu itemAtIndex:1].submenu, @"window menu designation failed")) return 1;
        if (require(elisa_appkit_canvas_render_headless(opened, 0, 200, 100), @"off-screen presentation failed")) return 1;
        if (require(test_frame_count > 0, @"off-screen frame did not draw")) return 1;
        ElisaCanvasDelegate *delegate = (__bridge ElisaCanvasDelegate *)(void *)delegateHandle;
        NSNotification *focusNotification = [NSNotification notificationWithName:NSWindowDidResignKeyNotification object:elisa_appkit_canvas_window(opened)];
        [delegate windowDidResignKey:focusNotification];
        if (require(test_window_focused == 0 && test_focus_window == opened,
                    @"window focus loss did not carry its identity to Elisa")) return 1;
        [delegate windowDidBecomeKey:focusNotification];
        if (require(test_window_focused == 1 && test_focus_window == opened,
                    @"window focus gain did not carry its identity to Elisa")) return 1;
        [delegate windowDidMove:focusNotification];
        if (require(test_environment_window == opened,
                    @"window environment change did not carry its identity to Elisa")) return 1;
        [delegate windowDidChangeBackingProperties:focusNotification];
        if (require(test_environment_window == opened,
                    @"backing change did not carry its identity to Elisa")) return 1;
        test_closed_window = 0;
        NSNotification *closeNotification = [NSNotification notificationWithName:NSWindowWillCloseNotification object:elisa_appkit_canvas_window(opened)];
        [delegate windowWillClose:closeNotification];
        if (require(test_closed_window == opened, @"window close identity did not reach Elisa")) return 1;
        if (require(!elisa_appkit_canvas_render_headless(
                         opened, (size_t)(__bridge void *)@"/elisa-ui-missing-directory/frame.png", 200, 100), @"snapshot failure did not cross the FFI boundary")) return 1;
        NSEvent *move = [NSEvent mouseEventWithType:NSEventTypeMouseMoved
            location:NSMakePoint(40, 20) modifierFlags:0 timestamp:0
            windowNumber:[elisa_appkit_canvas_window(opened) windowNumber] context:nil eventNumber:0
            clickCount:0 pressure:0.0];
        [elisa_appkit_canvas_view(opened) mouseEntered:move];
        if (require(test_pointer_kind == 0 && test_input_window == opened,
                    @"pointer entry did not cross the Elisa event path with its identity")) return 1;
        [elisa_appkit_canvas_view(opened) mouseMoved:move];
        if (require(test_pointer_kind == 0 && test_input_window == opened,
                    @"pointer motion did not cross the Elisa event path with its identity")) return 1;
        NSEvent *singleClick = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
            location:NSMakePoint(40, 20) modifierFlags:0 timestamp:0
            windowNumber:[elisa_appkit_canvas_window(opened) windowNumber] context:nil eventNumber:1
            clickCount:1 pressure:1.0];
        [elisa_appkit_canvas_view(opened) mouseDown:singleClick];
        if (require(test_click_button == 0 && test_click_count == 1 && test_input_window == opened,
                    @"single click facts did not reach Elisa with their identity")) return 1;
        NSEvent *doubleClick = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
            location:NSMakePoint(40, 20) modifierFlags:0 timestamp:0
            windowNumber:[elisa_appkit_canvas_window(opened) windowNumber] context:nil eventNumber:2
            clickCount:2 pressure:1.0];
        [elisa_appkit_canvas_view(opened) mouseDown:doubleClick];
        if (require(test_click_button == 0 && test_click_count == 2 && test_input_window == opened,
                    @"native click facts did not reach Elisa with their identity")) return 1;
        NSEvent *rightClick = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown
            location:NSMakePoint(40, 20) modifierFlags:0 timestamp:0
            windowNumber:[elisa_appkit_canvas_window(opened) windowNumber] context:nil eventNumber:3
            clickCount:2 pressure:1.0];
        [elisa_appkit_canvas_view(opened) rightMouseDown:rightClick];
        if (require(test_pointer_kind == 1 && test_pointer_button == (int)rightClick.buttonNumber &&
                        test_input_window == opened,
                    @"right-button raw identity did not cross the pointer FFI")) return 1;
        if (require(test_click_button == (int)rightClick.buttonNumber && test_click_count == 2,
                    @"right-button click facts did not reach Elisa")) return 1;
        NSEvent *rightRelease = [NSEvent mouseEventWithType:NSEventTypeRightMouseUp
            location:NSMakePoint(40, 20) modifierFlags:0 timestamp:0
            windowNumber:[elisa_appkit_canvas_window(opened) windowNumber] context:nil eventNumber:4
            clickCount:2 pressure:0.0];
        [elisa_appkit_canvas_view(opened) rightMouseUp:rightRelease];
        if (require(test_pointer_kind == 2 && test_pointer_button == (int)rightRelease.buttonNumber &&
                        test_input_window == opened,
                    @"right-button release did not cross the pointer FFI")) return 1;
        NSEvent *exit = [NSEvent mouseEventWithType:NSEventTypeMouseMoved
            location:NSMakePoint(40, 20) modifierFlags:0 timestamp:0
            windowNumber:[elisa_appkit_canvas_window(opened) windowNumber] context:nil eventNumber:5
            clickCount:0 pressure:0.0];
        [elisa_appkit_canvas_view(opened) mouseExited:exit];
        if (require(test_pointer_kind == 3 && test_pointer_button == 0 && test_input_window == opened,
                    @"pointer exit did not cross the Elisa event path")) return 1;
        NSArray *children = [elisa_appkit_canvas_view(opened) accessibilityChildren];
        if (require(children.count == 3, @"semantic children missing")) return 1;

        ElisaAccessibilityElement *first = children[0];
        if (require([first.accessibilityRole isEqualToString:NSAccessibilitySliderRole], @"wrong slider role")) return 1;
        if (require([first.accessibilityIdentifier isEqualToString:@"elisa-ui-7"], @"accessibility identifier did not cross the FFI")) return 1;
        if (require([first.accessibilityHelp isEqualToString:@"Adjust preview intensity"], @"help text missing")) return 1;
        NSString *tooltip = [(id)first view:(NSView *)first stringForToolTip:0 point:NSZeroPoint userData:NULL];
        if (require([tooltip isEqualToString:@"tooltip supplied by Elisa"] && test_tooltip_calls == 1 &&
                        test_input_window == opened,
                    @"tooltip text did not come from Elisa with its window identity")) return 1;
        if (require(fabs([first.accessibilityValue floatValue] - 0.25f) < 0.001f, @"wrong initial value")) return 1;
        first.accessibilityValue = @0.65f;
        if (require(fabs(test_slider_value - 0.65f) < 0.001f && fabs([first.accessibilityValue floatValue] - 0.65f) < 0.001f,
                    @"writable accessibility slider value did not reach Elisa")) return 1;
        ElisaAccessibilityElement *textField = children[1];
        if (require([textField.accessibilityRole isEqualToString:NSAccessibilityTextFieldRole], @"wrong text-field role")) return 1;
        if (require([textField.accessibilityValue isEqualToString:@"Hello"], @"wrong editable value")) return 1;
        ElisaAccessibilityElement *secureField = children[2];
        if (require([secureField.accessibilityRole isEqualToString:NSAccessibilityTextFieldRole], @"wrong secure-field role")) return 1;
        if (require([secureField.accessibilitySubrole isEqualToString:NSAccessibilitySecureTextFieldSubrole], @"secure-field subrole missing")) return 1;
        if (require([secureField.accessibilityValue isEqualToString:@"••••"], @"secure accessibility value was not masked")) return 1;
        textField.accessibilityValue = @"World";
        if (require(strcmp(test_text, "World") == 0, @"writable accessibility value did not reach the app")) return 1;
        textField.accessibilitySelectedTextRange = NSMakeRange(1, 3);
        if (require(test_selection_start == 1 && test_selection_end == 4, @"writable accessibility selection did not reach Elisa")) return 1;
        textField.accessibilitySelectedTextRange = NSMakeRange(5, 0);
        textField.accessibilitySelectedTextRange = NSMakeRange(999, 999);
        if (require(test_selection_start == 5 && test_selection_end == 5 &&
                        NSEqualRanges(textField.accessibilitySelectedTextRange, NSMakeRange(5, 0)),
                    @"oversized accessibility selection was not normalized by Elisa")) return 1;
        test_allow_text_mutation = 0;
        textField.accessibilityValue = @"rejected";
        if (require(strcmp(test_text, "World") == 0 && [textField.accessibilityValue isEqualToString:@"World"],
                    @"rejected accessibility value changed native state")) return 1;
        textField.accessibilitySelectedTextRange = NSMakeRange(0, 2);
        if (require(test_selection_start == 5 && test_selection_end == 5,
                    @"rejected accessibility selection changed native state")) return 1;
        test_allow_text_mutation = 1;
        NSObject *invalidInput = [NSObject new];
        [elisa_appkit_canvas_view(opened) insertText:invalidInput replacementRange:NSMakeRange(NSNotFound, 0)];
        if (require(strcmp(test_text, "World") == 0, @"invalid text input was not ignored")) return 1;
        [elisa_appkit_canvas_view(opened) setMarkedText:invalidInput selectedRange:NSMakeRange(0, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
        if (require(strcmp(test_text, "World") == 0 && !elisa_appkit_canvas_view(opened).hasMarkedText,
                    @"invalid marked text input was not ignored")) return 1;
        NSArray *markedAttributes = [elisa_appkit_canvas_view(opened) validAttributesForMarkedText];
        if (require(markedAttributes != nil && markedAttributes.count == 0,
                    @"marked-text attributes did not come from Elisa")) return 1;
        [elisa_appkit_canvas_view(opened) insertText:@"é" replacementRange:NSMakeRange(NSNotFound, 0)];
        if (require(strcmp(test_text, "Worldé") == 0 && test_input_window == opened,
                    @"Unicode text commit did not reach the app with its identity")) return 1;
        if (require(NSEqualRanges(elisa_appkit_canvas_view(opened).selectedRange, NSMakeRange(6, 0)), @"UTF-8 caret did not convert to UTF-16")) return 1;
        NSAttributedString *attributedInput = [[NSAttributedString alloc] initWithString:@"!"];
        [elisa_appkit_canvas_view(opened) insertText:attributedInput replacementRange:NSMakeRange(NSNotFound, 0)];
        if (require(strcmp(test_text, "Worldé!") == 0 &&
                        NSEqualRanges(elisa_appkit_canvas_view(opened).selectedRange, NSMakeRange(7, 0)),
                    @"attributed text commit was not normalized by Elisa")) return 1;
        NSRange actualRange = NSMakeRange(NSNotFound, 0);
        NSAttributedString *substring = [elisa_appkit_canvas_view(opened) attributedSubstringForProposedRange:NSMakeRange(5, 1) actualRange:&actualRange];
        if (require([substring.string isEqualToString:@"é"] && NSEqualRanges(actualRange, NSMakeRange(5, 1)), @"Unicode substring did not come from Elisa range slicing")) return 1;
        actualRange = NSMakeRange(NSNotFound, 0);
        (void)[elisa_appkit_canvas_view(opened) firstRectForCharacterRange:NSMakeRange(4, 2) actualRange:&actualRange];
        if (require(NSEqualRanges(actualRange, NSMakeRange(4, 2)), @"candidate rect range length did not come from Elisa range slicing")) return 1;
        test_allows_readback = 0;
        if (require([elisa_appkit_canvas_view(opened) attributedSubstringForProposedRange:NSMakeRange(0, 1) actualRange:NULL] == nil, @"secure substring readback was not denied")) return 1;
        test_text_focused = 0;
        if (require([elisa_appkit_canvas_view(opened) characterIndexForPoint:NSMakePoint(40, 20)] == NSNotFound,
                    @"unfocused character lookup did not stay in Elisa policy")) return 1;
        test_text_focused = 1;
        actualRange = NSMakeRange(NSNotFound, 0);
        test_text_focused = 0;
        if (require(NSEqualRects([elisa_appkit_canvas_view(opened) firstRectForCharacterRange:NSMakeRange(0, 1) actualRange:&actualRange], NSZeroRect) &&
                        NSEqualRanges(actualRange, NSMakeRange(NSNotFound, 0)),
                    @"unfocused candidate-rect lookup did not stay in Elisa policy")) return 1;
        test_text_focused = 1;
        strcpy(test_text, "secret");
        test_selection_start = 0;
        test_selection_end = 6;
        [elisa_appkit_canvas_view(opened) cut:nil];
        if (require(strcmp(test_text, "secret") == 0, @"disabled secure Cut destroyed text without exporting it")) return 1;
        test_allows_readback = 1;
        strcpy(test_text, "Worldé");

        [elisa_appkit_canvas_view(opened) selectAll:nil];
        if (require(NSEqualRanges(elisa_appkit_canvas_view(opened).selectedRange, NSMakeRange(0, 6)), @"Select All did not cover the field")) return 1;
        [elisa_appkit_canvas_view(opened) copy:nil];
        if (require([[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:@"Worldé"], @"Copy did not write selected Unicode text")) return 1;
        [[NSPasteboard generalPasteboard] clearContents];
        [[NSPasteboard generalPasteboard] setString:@"keep" forType:NSPasteboardTypeString];
        NSObject *invalidPasteboardType = [NSObject new];
        if (require(!elisa_appkit_canvas_clipboard_write(
                        (size_t)(__bridge void *)@"discard-me",
                        (size_t)(__bridge void *)invalidPasteboardType),
                    @"invalid clipboard type was accepted")) return 1;
        if (require([[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:@"keep"],
                    @"invalid clipboard type destroyed existing contents")) return 1;
        if (require(elisa_appkit_canvas_clipboard_read(
                        (size_t)(__bridge void *)invalidPasteboardType) == 0,
                    @"invalid clipboard type was readable")) return 1;
        if (require(elisa_appkit_canvas_clipboard_write(
                        (size_t)(__bridge void *)@"",
                        (size_t)(__bridge void *)NSPasteboardTypeString), @"empty clipboard write failed")) return 1;
        if (require([[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:@""], @"empty clipboard write did not clear the pasteboard")) return 1;
        [elisa_appkit_canvas_view(opened) insertText:@"Next" replacementRange:NSMakeRange(NSNotFound, 0)];
        if (require(strcmp(test_text, "Next") == 0, @"typing did not replace the selection")) return 1;

        strcpy(test_text, "Cafe");
        test_selection_start = test_selection_end = 4;
        [elisa_appkit_canvas_view(opened) setMarkedText:@"é" selectedRange:NSMakeRange(1, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
        if (require(strcmp(test_text, "Cafeé") == 0, @"marked text was not inserted")) return 1;
        if (require(NSEqualRanges(elisa_appkit_canvas_view(opened).markedRange, NSMakeRange(4, 1)), @"marked range is wrong")) return 1;
        if (require(test_marked_start == 4 && test_marked_end == 6, @"marked range did not convert to UTF-8 bytes")) return 1;
        [elisa_appkit_canvas_view(opened) setMarkedText:@"ø" selectedRange:NSMakeRange(1, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
        if (require(strcmp(test_text, "Cafeø") == 0, @"marked text update did not replace its range")) return 1;
        [elisa_appkit_canvas_view(opened) insertText:@"å" replacementRange:NSMakeRange(NSNotFound, 0)];
        if (require(strcmp(test_text, "Cafeå") == 0, @"committed text did not replace marked text")) return 1;
        if (require(!elisa_appkit_canvas_view(opened).hasMarkedText, @"marked range survived commit")) return 1;
        if (require(test_marked_start == 0 && test_marked_end == 0, @"painted marked range survived commit")) return 1;
        [elisa_appkit_canvas_view(opened) undo:nil];
        [elisa_appkit_canvas_view(opened) redo:nil];
        if (require(test_undo_calls == 1 && test_redo_calls == 1, @"Undo/Redo actions did not cross the FFI boundary")) return 1;
        [elisa_appkit_canvas_view(opened) doCommandBySelector:@selector(moveLeftAndModifySelection:)];
        if (require(test_text_selector == 3, @"native text selector identity did not cross the FFI boundary")) return 1;
        [elisa_appkit_canvas_view(opened) doCommandBySelector:@selector(moveWordRightAndModifySelection:)];
        if (require(test_text_selector == 17, @"native word-selection identity did not cross the FFI boundary")) return 1;
        [elisa_appkit_canvas_view(opened) doCommandBySelector:@selector(deleteWordBackward:)];
        if (require(test_text_selector == 18, @"native word-deletion identity did not cross the FFI boundary")) return 1;

        test_invalid_attributed_substring = 1;
        if (require([elisa_appkit_canvas_view(opened)
                      attributedSubstringForProposedRange:NSMakeRange(0, 1)
                                              actualRange:NULL] == nil,
                    @"invalid attributed-substring object was accepted")) return 1;
        test_invalid_attributed_substring = 0;
        if (require(test_invalid_attributed_substring_released,
                    @"invalid attributed-substring object leaked")) return 1;

        test_slider_value = 0.75f;
        test_text_focused = 0;
        test_selection_start = test_selection_end = 0;
        if (require(elisa_appkit_canvas_render_headless(opened, 0, 200, 100), @"second off-screen presentation failed")) return 1;
        NSArray *secondChildren = [elisa_appkit_canvas_view(opened) accessibilityChildren];
        ElisaAccessibilityElement *second = secondChildren[0];
        ElisaAccessibilityElement *secondTextField = secondChildren[1];
        ElisaAccessibilityElement *secondSecureField = secondChildren[2];
        if (require(first == second, @"semantic identity changed across frames")) return 1;
        if (require(textField == secondTextField, @"text-field identity changed across frames")) return 1;
        if (require(secureField == secondSecureField, @"secure-field identity changed across frames")) return 1;
        if (require(fabs([second.accessibilityValue floatValue] - 0.75f) < 0.001f, @"value did not update")) return 1;
        if (require([secondTextField.accessibilitySelectedText isEqualToString:@""] && NSEqualRanges(secondTextField.accessibilitySelectedTextRange, NSMakeRange(0, 0)), @"blurred text field retained stale accessibility selection")) return 1;

        // The production sync path now asks Elisa when a reused node changes
        // value kind, then invokes this narrow Cocoa primitive. Verify that
        // clearing removes every role-specific slot without replacing the
        // native semantic object.
        elisa_appkit_canvas_accessibility_clear_value((size_t)(__bridge void *)second,
                                                      NSNotFound, 0);
        if (require(second.accessibilityValue == nil && second.accessibilitySelectedText == nil &&
                        NSEqualRanges(second.accessibilitySelectedTextRange, NSMakeRange(NSNotFound, 0)) &&
                        second.accessibilityMinValue == nil && second.accessibilityMaxValue == nil,
                    @"accessibility value reset did not clear native slots")) return 1;

        if (require([second accessibilityPerformIncrement] && test_input_window == opened,
                    @"increment action did not carry its window identity")) return 1;
        if (require(fabs(test_slider_value - 0.80f) < 0.001f, @"increment action did not reach the app")) return 1;
        [elisa_appkit_canvas_window(opened) close];
        for (ElisaAccessibilityElement *element in secondChildren) {
            elisa_appkit_canvas_accessibility_release((size_t)(__bridge void *)element);
        }
        elisa_appkit_canvas_release_delegate(delegateHandle);
        elisa_appkit_canvas_release_window(opened);
    }
    puts("appkit canvas bridge: all checks passed");
    return 0;
}
