// Fragment of appkit_canvas_shim.m: SDK facts exported as read-only globals, then the
// window, menu, clipboard, redraw-timer and run-loop entry points Elisa drives.
//
// Not a translation unit of its own: appkit_canvas_shim.m #imports the fragments under
// canvas_shim/ in order so the shim stays ONE compilation unit. That is deliberate --
// the helpers are `static`, the retained Cocoa objects are private state, and
// test/appkit_canvas_bridge_test.m includes the whole unit because identity stability
// of those objects is the behaviour under test. Build scripts compile the umbrella only.

#import <Cocoa/Cocoa.h>

// Cocoa enum values and sentinels are ABI facts. Export them as read-only FFI
// globals so Elisa can assemble window, tracking and text-input policy without
// paying for a native accessor function for each SDK constant.
extern const int elisa_appkit_canvas_window_style_titled;
const int elisa_appkit_canvas_window_style_titled = NSWindowStyleMaskTitled;
extern const int elisa_appkit_canvas_window_style_closable;
const int elisa_appkit_canvas_window_style_closable = NSWindowStyleMaskClosable;
extern const int elisa_appkit_canvas_window_style_miniaturizable;
const int elisa_appkit_canvas_window_style_miniaturizable = NSWindowStyleMaskMiniaturizable;
extern const int elisa_appkit_canvas_window_style_resizable;
const int elisa_appkit_canvas_window_style_resizable = NSWindowStyleMaskResizable;
extern const int elisa_appkit_canvas_backing_store_buffered;
const int elisa_appkit_canvas_backing_store_buffered = NSBackingStoreBuffered;
extern const int elisa_appkit_canvas_activation_policy_regular;
const int elisa_appkit_canvas_activation_policy_regular = NSApplicationActivationPolicyRegular;
extern const int elisa_appkit_canvas_activation_policy_prohibited;
const int elisa_appkit_canvas_activation_policy_prohibited = NSApplicationActivationPolicyProhibited;
extern const int elisa_appkit_canvas_tabbing_mode_preferred;
const int elisa_appkit_canvas_tabbing_mode_preferred = NSWindowTabbingModePreferred;
extern const int elisa_appkit_canvas_tabbing_mode_disallowed;
const int elisa_appkit_canvas_tabbing_mode_disallowed = NSWindowTabbingModeDisallowed;
extern const size_t elisa_appkit_canvas_tracking_mouse_moved;
const size_t elisa_appkit_canvas_tracking_mouse_moved = NSTrackingMouseMoved;
extern const size_t elisa_appkit_canvas_tracking_mouse_entered_exited;
const size_t elisa_appkit_canvas_tracking_mouse_entered_exited = NSTrackingMouseEnteredAndExited;
extern const size_t elisa_appkit_canvas_tracking_active_in_key_window;
const size_t elisa_appkit_canvas_tracking_active_in_key_window = NSTrackingActiveInKeyWindow;
extern const size_t elisa_appkit_canvas_tracking_in_visible_rect;
const size_t elisa_appkit_canvas_tracking_in_visible_rect = NSTrackingInVisibleRect;
extern const size_t elisa_appkit_canvas_not_found;
const size_t elisa_appkit_canvas_not_found = NSNotFound;

// Window construction receives only dimensions and ABI style/backing facts.
// Framework text is assigned through the typed setter below after Elisa has
// installed the returned opaque handle.
size_t elisa_appkit_canvas_open(float width, float height,
                                int style, int backing, size_t *delegateHandle) {
    if (delegateHandle == NULL) return 0;
    *delegateHandle = 0;
    [NSApplication sharedApplication];
    NSRect rect = NSMakeRect(0, 0, width, height);
    NSWindowStyleMask styleMask = (NSWindowStyleMask)style;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:rect
        styleMask:styleMask
        backing:(NSBackingStoreType)backing defer:NO];
    if (window == nil) return 0;
    // View construction may synchronously report its initial frame. The
    // Elisa adapter owns the readiness guard and filters that callback
    // until app_init has completed.
    ElisaCanvasView *view = [[ElisaCanvasView alloc] initWithFrame:rect];
    ElisaCanvasDelegate *delegate = [ElisaCanvasDelegate new];
    if (view == nil || delegate == nil) return 0;
    [window setDelegate:delegate];
    [window setContentView:view];
    *delegateHandle = (size_t)(__bridge_retained void *)delegate;
    // Transfer the window retain to Elisa. All later operations receive
    // this explicit handle, so the native shim keeps no root owner.
    return (size_t)(__bridge_retained void *)window;
}

// Window text is framework-owned data. Keep conversion and validation in
// Elisa, then expose one typed Cocoa property write after the opaque window
// handle exists. Construction therefore remains limited to native object
// allocation and protocol attachment.
int elisa_appkit_canvas_set_title(size_t windowHandle, size_t title) {
    NSWindow *window = elisa_appkit_canvas_window(windowHandle);
    NSString *value = elisa_appkit_canvas_string(title);
    if (window == nil || value == nil) return 0;
    [window setTitle:value];
    return 1;
}

void elisa_appkit_canvas_release_window(size_t handle) {
    if (handle == 0) return;
    id object = (__bridge id)(void *)handle;
    if (![object isKindOfClass:[NSWindow class]]) return;
    // Transfer Elisa's +1 into ARC exactly once. Keeping the bridged value as
    // a strong local while also calling CFRelease would over-release it when
    // ARC tears that local down at function exit.
    (void)CFBridgingRelease((CFTypeRef)(void *)handle);
}

void elisa_appkit_canvas_release_delegate(size_t handle) {
    if (handle == 0) return;
    id object = (__bridge id)(void *)handle;
    if (![object isKindOfClass:[ElisaCanvasDelegate class]]) return;
    (void)CFBridgingRelease((CFTypeRef)(void *)handle);
}

void elisa_appkit_canvas_set_activation_policy(int policy) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:(NSApplicationActivationPolicy)policy];
}

void elisa_appkit_canvas_focus(size_t windowHandle) {
    NSWindow *window = elisa_appkit_canvas_window(windowHandle);
    ElisaCanvasView *view = elisa_appkit_canvas_view(windowHandle);
    if (window != nil && view != nil) {
        [window makeFirstResponder:view];
    }
}

void elisa_appkit_canvas_set_tabbing_mode(size_t windowHandle, int mode) {
    NSWindow *window = elisa_appkit_canvas_window(windowHandle);
    if (window != nil) {
        [window setTabbingMode:(NSWindowTabbingMode)mode];
    }
}

void elisa_appkit_canvas_set_restorable(size_t windowHandle, int restorable) {
    NSWindow *window = elisa_appkit_canvas_window(windowHandle);
    if (window != nil) {
        [window setRestorable:restorable != 0];
    }
}

// Elisa owns the retained window handle and therefore decides whether Cocoa
// may consume that ownership automatically when the user closes the window.
// The shim only performs the typed NSWindow property write at the boundary.
void elisa_appkit_canvas_set_released_when_closed(size_t windowHandle, int released) {
    NSWindow *window = elisa_appkit_canvas_window(windowHandle);
    if (window != nil) {
        [window setReleasedWhenClosed:released != 0];
    }
}

void elisa_appkit_canvas_center(size_t windowHandle) {
    NSWindow *window = elisa_appkit_canvas_window(windowHandle);
    if (window != nil) [window center];
}

size_t elisa_appkit_canvas_menus_begin(void) {
    return (size_t)(__bridge_retained void *)[NSMenu new];
}

// Menu labels arrive as borrowed opaque CFStrings created by Elisa. Cocoa
// retains them while creating the menu item; the bridge does not decode UTF-8.
size_t elisa_appkit_canvas_menu_add(size_t menuBar, size_t title, size_t emptyKeyEquivalent) {
    NSMenu *bar = (__bridge NSMenu *)(void *)menuBar;
    if (![bar isKindOfClass:[NSMenu class]]) return 0;
    NSString *value = elisa_appkit_canvas_string(title);
    NSString *emptyKey = elisa_appkit_canvas_string(emptyKeyEquivalent);
    if (value == nil || emptyKey == nil) return 0;
    NSMenuItem *root = [[NSMenuItem alloc] initWithTitle:value action:NULL keyEquivalent:emptyKey];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:value];
    if (root == nil || menu == nil) return 0;
    [root setSubmenu:menu];
    [bar addItem:root];
    return (size_t)(__bridge void *)menu;
}

void elisa_appkit_canvas_menu_set_windows(size_t menu) {
    NSMenu *value = (__bridge NSMenu *)(void *)menu;
    if (![value isKindOfClass:[NSMenu class]]) return;
    [NSApp setWindowsMenu:value];
}

static void elisa_appkit_canvas_menu_add_item_title(size_t menu, NSString *title,
                                                     NSString *keyEquivalent,
                                                     size_t actionHandle, size_t modifiers) {
    if (title == nil || keyEquivalent == nil) return;
    NSMenu *value = (__bridge NSMenu *)(void *)menu;
    if (![value isKindOfClass:[NSMenu class]]) return;
    // Elisa resolves the selector name through the Objective-C runtime FFI.
    // The bridge only casts the already-registered ABI token and assigns it to
    // NSMenuItem; selector naming policy and registration stay out of native
    // framework code.
    SEL action = actionHandle == 0 ? NULL : (SEL)(void *)actionHandle;
    NSMenuItem *item = [value addItemWithTitle:title action:action keyEquivalent:keyEquivalent];
    if (item != nil) item.keyEquivalentModifierMask = (NSEventModifierFlags)modifiers;
}

void elisa_appkit_canvas_menu_add_item(size_t menu, size_t title,
                                        size_t keyEquivalent, size_t actionHandle,
                                        size_t modifiers) {
    NSString *value = elisa_appkit_canvas_string(title);
    NSString *key = elisa_appkit_canvas_string(keyEquivalent);
    elisa_appkit_canvas_menu_add_item_title(menu, value, key, actionHandle, modifiers);
}

extern const size_t elisa_appkit_canvas_modifier_command;
const size_t elisa_appkit_canvas_modifier_command = NSEventModifierFlagCommand;
extern const size_t elisa_appkit_canvas_modifier_shift;
const size_t elisa_appkit_canvas_modifier_shift = NSEventModifierFlagShift;
extern const size_t elisa_appkit_canvas_modifier_option;
const size_t elisa_appkit_canvas_modifier_option = NSEventModifierFlagOption;
extern const size_t elisa_appkit_canvas_modifier_control;
const size_t elisa_appkit_canvas_modifier_control = NSEventModifierFlagControl;
extern const size_t elisa_appkit_canvas_modifier_device_independent_mask;
const size_t elisa_appkit_canvas_modifier_device_independent_mask = NSEventModifierFlagDeviceIndependentFlagsMask;

void elisa_appkit_canvas_menu_add_separator(size_t menu) {
    NSMenu *value = (__bridge NSMenu *)(void *)menu;
    if (![value isKindOfClass:[NSMenu class]]) return;
    NSMenuItem *separator = [NSMenuItem separatorItem];
    if (separator != nil) [value addItem:separator];
}

void elisa_appkit_canvas_menus_commit(size_t menuBar) {
    NSMenu *bar = (__bridge NSMenu *)(void *)menuBar;
    if (![bar isKindOfClass:[NSMenu class]]) return;
    // menus_begin transfers one retain to Elisa. Once AppKit owns the main
    // menu, consume that retain at scope exit instead of keeping hidden global
    // state in the bridge.
    NSMenu *owned = (__bridge_transfer NSMenu *)(void *)menuBar;
    [NSApp setMainMenu:owned];
}

// Clipboard writes arrive as a borrowed opaque CFString created by Elisa.
// Reading still converts Cocoa text back to bytes at the native boundary, but
// outbound framework text no longer performs UTF-8 decoding in Objective-C.
int elisa_appkit_canvas_clipboard_write(size_t text, size_t pasteboard_type) {
    if (text == 0 || pasteboard_type == 0) return 0;
    NSString *value = elisa_appkit_canvas_string(text);
    NSString *type = elisa_appkit_canvas_string(pasteboard_type);
    // Validate both borrowed objects before mutating the pasteboard. A bad
    // FFI handle must fail closed without destroying a previously copied
    // value, and the native bridge must never message an arbitrary object as
    // though it were an NSString.
    if (![value isKindOfClass:[NSString class]] || ![type isKindOfClass:[NSString class]]) return 0;
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    return [pasteboard setString:value forType:type];
}

// Return a retained native string for Elisa to encode through CoreFoundation.
// The read direction is the one place where Cocoa owns the source text, so the
// bridge transfers object ownership rather than deciding byte truncation.
size_t elisa_appkit_canvas_clipboard_read(size_t pasteboard_type) {
    if (pasteboard_type == 0) return 0;
    NSString *type = elisa_appkit_canvas_string(pasteboard_type);
    if (type == nil) return 0;
    NSString *text = [[NSPasteboard generalPasteboard] stringForType:type];
    if (text == nil) return 0;
    return (size_t)CFBridgingRetain(text);
}

size_t elisa_appkit_canvas_schedule_redraw(float delay, size_t run_loop_mode,
                                           size_t windowHandle,
                                           uint32_t generation) {
    NSString *mode = elisa_appkit_canvas_string(run_loop_mode);
    if (mode == nil || elisa_appkit_canvas_window(windowHandle) == nil) return 0;
    // Capture only the opaque root handle and Elisa lifecycle generation in
    // the timer block. The timer is retained by Elisa until
    // delivery/cancellation, so no native view is captured or kept alive by
    // the scheduler.
    NSTimer *timer = [NSTimer timerWithTimeInterval:delay repeats:NO block:^(NSTimer *fired) {
        (void)fired;
        // Timer delivery re-enters Elisa so lifecycle and stale-window policy
        // stay with the retained framework state rather than this block.
        elisa_appkit_canvas_timer_fired(windowHandle, generation,
                                        (size_t)(__bridge void *)fired);
    }];
    if (timer == nil) return 0;
    [NSRunLoop.mainRunLoop addTimer:timer forMode:mode];
    // Transfer one retain to Elisa, which releases it through the matching
    // cancellation primitive after the frame is delivered or the window
    // closes. No hidden native timer slot remains.
    return (size_t)(__bridge_retained void *)timer;
}

void elisa_appkit_canvas_cancel_redraw(size_t handle) {
    if (handle == 0) return;
    id object = (__bridge id)(void *)handle;
    if (![object isKindOfClass:[NSTimer class]]) return;
    NSTimer *timer = (__bridge_transfer NSTimer *)(void *)handle;
    [timer invalidate];
}

void elisa_appkit_canvas_set_min_size(size_t windowHandle, float width, float height) {
    NSWindow *window = elisa_appkit_canvas_window(windowHandle);
    if (window != nil) [window setContentMinSize:NSMakeSize(width, height)];
}

int elisa_appkit_canvas_present(size_t windowHandle) {
    NSWindow *window = elisa_appkit_canvas_window(windowHandle);
    if (window == nil || elisa_appkit_canvas_view(windowHandle) == nil) return 0;
    [window makeKeyAndOrderFront:nil];
    return 1;
}

void elisa_appkit_canvas_activate(void) {
    [NSApp activateIgnoringOtherApps:YES];
}
void elisa_appkit_canvas_run(void) {
    [NSApp run];
}
void elisa_appkit_canvas_stop(void) {
    [NSApp stop:nil];
}
void elisa_appkit_canvas_redraw(size_t windowHandle) {
    ElisaCanvasView *view = elisa_appkit_canvas_view(windowHandle);
    if (view != nil) [view setNeedsDisplay:YES];
}

// Cursor rectangles are transient NSView state. Elisa owns the semantic list
// and supplies each resolved frame/cursor pair; this function performs only
// the typed Cocoa insertion for the explicit window handle.
void elisa_appkit_canvas_add_cursor_rect(size_t windowHandle, float x, float y,
                                         float width, float height, size_t cursorHandle) {
    ElisaCanvasView *view = elisa_appkit_canvas_view(windowHandle);
    NSCursor *cursor = elisa_appkit_canvas_cursor(cursorHandle);
    if (view == nil || cursor == nil) return;
    [view addCursorRect:NSMakeRect(x, y, width, height) cursor:cursor];
}

void elisa_appkit_canvas_close(size_t windowHandle) {
    NSWindow *window = elisa_appkit_canvas_window(windowHandle);
    if (window != nil) [window performClose:nil];
}
void elisa_appkit_canvas_accessibility_reset(size_t windowHandle) {
    ElisaCanvasView *view = elisa_appkit_canvas_view(windowHandle);
    if (view != nil) [view removeAllToolTips];
}
