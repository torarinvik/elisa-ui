// The Objective-C half of the AppKit backend.
//
// WHY A SHIM AND NOT objc_msgSend FROM ELISA. objc_msgSend has no single
// signature -- on arm64 every call must be cast to the exact prototype of the
// method being sent, and getting that wrong is a silent ABI mismatch rather than
// a link error. That cast is a C-language operation. So the Objective-C lives
// here and Elisa sees a flat, typed C API, exactly as it does for SDL3.
//
// Elisa owns the index -> opaque-handle table in its retained control arena.
// This file receives those handles and only resolves them to Cocoa objects at
// the boundary; no native bookkeeping mirrors the framework arena.
//
// COORDINATES ARE FLIPPED HERE. elisa-ui lays out top-left origin, y growing
// down, like every other UI toolkit and like the wasm canvas. AppKit's default
// is bottom-left, y growing up. Rather than flip in the layout pass (which would
// make every other backend wrong) each container view returns YES from
// isFlipped, so a child's frame is used verbatim.

#import <Cocoa/Cocoa.h>

// Coordinate policy belongs to the widget framework. Objective-C only adapts
// the Cocoa protocol method to the value Elisa selected.
extern int elisa_appkit_view_is_flipped(void);

// A container whose origin is top-left, so a laid-out frame needs no conversion.
@interface ElisaFlippedView : NSView
@end
@implementation ElisaFlippedView
- (BOOL)isFlipped { return elisa_appkit_view_is_flipped() != 0; }
@end

static id elisa_appkit_object(size_t handle) {
    if (handle == 0) return nil;
    return (__bridge id)(void *)handle;
}

// Text values cross the FFI as borrowed opaque CoreFoundation objects created
// by Elisa. Resolve and validate the dynamic type once at the native boundary;
// every constructor, setter and introspection path can then treat the result as
// an NSString without reopening an unchecked bridge cast.
static NSString *elisa_appkit_string(size_t handle) {
    if (handle == 0) return nil;
    id object = (__bridge id)(void *)handle;
    return [object isKindOfClass:[NSString class]] ? object : nil;
}

// Resolve a recorded object for headless introspection. Production attachment
// uses the explicit typed attach entry points below; this bookkeeping branch is
// only for read-back checks.
static NSView *elisa_container_for(size_t handle) {
    id object = elisa_appkit_object(handle);
    if (object == nil) return nil;
    if ([object isKindOfClass:[NSWindow class]]) {
        return [(NSWindow *)object contentView];
    }
    if ([object isKindOfClass:[NSScrollView class]]) {
        return [(NSScrollView *)object documentView];
    }
    return (NSView *)object;
}

void elisa_appkit_init(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
    }
}

// AppKit's activation enum is an ABI fact. Elisa selects the policy and sends
// the chosen value back through this setter, keeping application behavior out
// of the Objective-C object bridge.
int elisa_appkit_activation_policy_regular(void) {
    return (int)NSApplicationActivationPolicyRegular;
}

void elisa_appkit_set_activation_policy(int policy) {
    @autoreleasepool {
        [NSApp setActivationPolicy:(NSApplicationActivationPolicy)policy];
    }
}

// Constructors return a retained opaque handle. Elisa stores and releases it
// from its own control arena; ARC therefore has no platform-side table to keep.
static size_t elisa_appkit_retain(id object) {
    return object == nil ? 0 : (size_t)(__bridge_retained void *)object;
}

void elisa_appkit_attach_to_window(size_t handle, size_t parent) {
    NSView *view = (NSView *)elisa_appkit_object(handle);
    id object = elisa_appkit_object(parent);
    NSView *container = [object isKindOfClass:[NSWindow class]] ? [(NSWindow *)object contentView] : nil;
    if (container != nil && view != nil) [container addSubview:view];
}

void elisa_appkit_attach_to_scroll_view(size_t handle, size_t parent) {
    NSView *view = (NSView *)elisa_appkit_object(handle);
    id object = elisa_appkit_object(parent);
    NSView *container = [object isKindOfClass:[NSScrollView class]] ? [(NSScrollView *)object documentView] : nil;
    if (container != nil && view != nil) [container addSubview:view];
}

void elisa_appkit_attach_to_view(size_t handle, size_t parent) {
    NSView *view = (NSView *)elisa_appkit_object(handle);
    id object = elisa_appkit_object(parent);
    NSView *container = [object isKindOfClass:[NSView class]] ? (NSView *)object : nil;
    if (container != nil && view != nil) [container addSubview:view];
}

// Cocoa's style values are ABI facts, not framework policy. Elisa combines
// these values into the requested decoration mask and passes the result back
// to the shim; the native side only casts the already-resolved mask.
int elisa_appkit_window_style_titled(void) {
    return (int)NSWindowStyleMaskTitled;
}

int elisa_appkit_window_style_closable(void) {
    return (int)NSWindowStyleMaskClosable;
}

int elisa_appkit_window_style_miniaturizable(void) {
    return (int)NSWindowStyleMaskMiniaturizable;
}

int elisa_appkit_window_style_resizable(void) {
    return (int)NSWindowStyleMaskResizable;
}

int elisa_appkit_window_style_utility(void) {
    return (int)NSWindowStyleMaskUtilityWindow;
}

int elisa_appkit_bezel_style_rounded(void) {
    return (int)NSBezelStyleRounded;
}

int elisa_appkit_button_type_push_on_push_off(void) {
    return (int)NSButtonTypePushOnPushOff;
}

int elisa_appkit_control_state_on(void) {
    return (int)NSControlStateValueOn;
}

int elisa_appkit_control_state_off(void) {
    return (int)NSControlStateValueOff;
}

int elisa_appkit_progress_style_bar(void) {
    return (int)NSProgressIndicatorStyleBar;
}

int elisa_appkit_backing_store_buffered(void) {
    return (int)NSBackingStoreBuffered;
}

size_t elisa_appkit_create_window_with_style(int style, int backing,
                                             float width, float height) {
    @autoreleasepool {
        NSRect content = NSMakeRect(0, 0, width, height);
        NSWindow *window = [[NSWindow alloc]
            initWithContentRect:content
                      styleMask:(NSWindowStyleMask)style
                        backing:(NSBackingStoreType)backing
                          defer:NO];
        if (window == nil) return 0;
        [window setContentView:[[ElisaFlippedView alloc] initWithFrame:content]];
        return elisa_appkit_retain(window);
    }
}

size_t elisa_appkit_create_panel_window(int style, int backing,
                                        int floating, int becomes_key_only,
                                        float width, float height) {
    @autoreleasepool {
        NSRect content = NSMakeRect(0, 0, width, height);
        NSPanel *panel = [[NSPanel alloc]
            initWithContentRect:content
                      styleMask:(NSWindowStyleMask)style
                        backing:(NSBackingStoreType)backing
                          defer:NO];
        if (panel == nil) return 0;
        [panel setFloatingPanel:floating != 0];
        [panel setBecomesKeyOnlyIfNeeded:becomes_key_only != 0];
        [panel setContentView:[[ElisaFlippedView alloc] initWithFrame:content]];
        return elisa_appkit_retain(panel);
    }
}

size_t elisa_appkit_create_panel(void) {
    @autoreleasepool {
        return elisa_appkit_retain([[ElisaFlippedView alloc] initWithFrame:NSZeroRect]);
    }
}

// The scrollbar policy is resolved by Elisa from the widget axis. The native
// side only constructs the NSScrollView and applies the already-resolved bits.
size_t elisa_appkit_create_scroll_view(int vertical, int horizontal) {
    @autoreleasepool {
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
        [scroll setHasVerticalScroller:vertical != 0];
        [scroll setHasHorizontalScroller:horizontal != 0];
        [scroll setDocumentView:[[ElisaFlippedView alloc] initWithFrame:NSZeroRect]];
        return elisa_appkit_retain(scroll);
    }
}

size_t elisa_appkit_create_label(size_t text) {
    @autoreleasepool {
        NSString *value = elisa_appkit_string(text);
        if (value == nil) return 0;
        return elisa_appkit_retain([NSTextField labelWithString:value]);
    }
}

size_t elisa_appkit_create_push_button(int bezel_style, size_t text) {
    @autoreleasepool {
        NSString *value = elisa_appkit_string(text);
        if (value == nil) return 0;
        NSButton *button = [NSButton buttonWithTitle:value target:nil action:nil];
        [button setBezelStyle:(NSBezelStyle)bezel_style];
        return elisa_appkit_retain(button);
    }
}

size_t elisa_appkit_create_toggle_button(int button_type, size_t text) {
    @autoreleasepool {
        NSString *value = elisa_appkit_string(text);
        if (value == nil) return 0;
        NSButton *button = [NSButton buttonWithTitle:value target:nil action:nil];
        [button setButtonType:(NSButtonType)button_type];
        return elisa_appkit_retain(button);
    }
}

size_t elisa_appkit_create_checkbox(size_t text) {
    @autoreleasepool {
        NSString *value = elisa_appkit_string(text);
        if (value == nil) return 0;
        return elisa_appkit_retain([NSButton checkboxWithTitle:value target:nil action:nil]);
    }
}

size_t elisa_appkit_create_radio_button(size_t text) {
    @autoreleasepool {
        NSString *value = elisa_appkit_string(text);
        if (value == nil) return 0;
        return elisa_appkit_retain([NSButton radioButtonWithTitle:value target:nil action:nil]);
    }
}

size_t elisa_appkit_create_text_field(size_t text) {
    @autoreleasepool {
        NSString *value = elisa_appkit_string(text);
        if (value == nil) return 0;
        return elisa_appkit_retain([NSTextField textFieldWithString:value]);
    }
}

size_t elisa_appkit_create_slider(float low, float high, float value) {
    @autoreleasepool {
        return elisa_appkit_retain([NSSlider sliderWithValue:value minValue:low maxValue:high target:nil action:nil]);
    }
}

size_t elisa_appkit_create_progress_bar(int progress_style, int indeterminate) {
    @autoreleasepool {
        NSProgressIndicator *bar = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
        [bar setStyle:(NSProgressIndicatorStyle)progress_style];
        [bar setIndeterminate:indeterminate != 0];
        return elisa_appkit_retain(bar);
    }
}

void elisa_appkit_set_window_frame(size_t handle, float width, float height) {
    @autoreleasepool {
        // A window is positioned by the OS; only its content size is ours.
        NSWindow *window = (NSWindow *)elisa_appkit_object(handle);
        if (![window isKindOfClass:[NSWindow class]]) return;
        [window setContentSize:NSMakeSize(width, height)];
        [[window contentView] setFrame:NSMakeRect(0, 0, width, height)];
    }
}

void elisa_appkit_set_view_frame(size_t handle, float x, float y, float width, float height) {
    @autoreleasepool {
        NSView *view = (NSView *)elisa_appkit_object(handle);
        if (![view isKindOfClass:[NSView class]]) return;
        [view setFrame:NSMakeRect(x, y, width, height)];
    }
}

// Elisa dispatches this only for a ScrollView. Keeping the document sizing as
// its own typed entry point removes a production policy branch over the
// framework enum from the native object bridge.
void elisa_appkit_set_scroll_document_frame(size_t handle, float width, float height) {
    @autoreleasepool {
        NSScrollView *scroll = (NSScrollView *)elisa_appkit_object(handle);
        if (![scroll isKindOfClass:[NSScrollView class]]) return;
        [[scroll documentView] setFrame:NSMakeRect(0, 0, width, height)];
    }
}

// Elisa creates the counted CFString through CoreFoundation FFI. The shim only
// borrows that opaque object long enough to assign it to the live Cocoa control;
// no UTF-8 policy or byte-to-string conversion remains in this bridge.
void elisa_appkit_set_window_title(size_t handle, size_t text) {
    @autoreleasepool {
        NSString *value = elisa_appkit_string(text);
        NSWindow *window = (NSWindow *)elisa_appkit_object(handle);
        if (value != nil && [window isKindOfClass:[NSWindow class]]) [window setTitle:value];
    }
}

void elisa_appkit_set_button_title(size_t handle, size_t text) {
    @autoreleasepool {
        NSString *value = elisa_appkit_string(text);
        NSButton *button = (NSButton *)elisa_appkit_object(handle);
        if (value != nil && [button isKindOfClass:[NSButton class]]) [button setTitle:value];
    }
}

void elisa_appkit_set_field_text(size_t handle, size_t text) {
    @autoreleasepool {
        NSString *value = elisa_appkit_string(text);
        NSTextField *field = (NSTextField *)elisa_appkit_object(handle);
        if (value != nil && [field isKindOfClass:[NSTextField class]]) [field setStringValue:value];
    }
}

void elisa_appkit_set_button_state(size_t handle, int state) {
    @autoreleasepool {
        NSButton *button = (NSButton *)elisa_appkit_object(handle);
        if ([button isKindOfClass:[NSButton class]]) [button setState:(NSControlStateValue)state];
    }
}

void elisa_appkit_set_slider_state(size_t handle, float low, float high, float value) {
    @autoreleasepool {
        NSSlider *slider = (NSSlider *)elisa_appkit_object(handle);
        if (![slider isKindOfClass:[NSSlider class]]) return;
        [slider setMinValue:low];
        [slider setMaxValue:high];
        [slider setDoubleValue:value];
    }
}

void elisa_appkit_set_progress_value(size_t handle, float value) {
    @autoreleasepool {
        NSProgressIndicator *bar = (NSProgressIndicator *)elisa_appkit_object(handle);
        if ([bar isKindOfClass:[NSProgressIndicator class]]) [bar setDoubleValue:value];
    }
}

// Show the window. Separated from the run loop so a headless check can realize a
// tree, assert it, and exit without ever presenting anything.
void elisa_appkit_present(size_t handle) {
    @autoreleasepool {
        NSWindow *window = (NSWindow *)elisa_appkit_object(handle);
        if (![window isKindOfClass:[NSWindow class]]) return;
        [window makeKeyAndOrderFront:nil];
    }
}

void elisa_appkit_activate(void) {
    @autoreleasepool {
        [NSApp activateIgnoringOtherApps:YES];
    }
}

void elisa_appkit_run(void) {
    @autoreleasepool { [NSApp run]; }
}

// --- introspection, for the headless test -------------------------------------
// What AppKit actually built, read back from the live objects rather than from
// anything this file remembered: a test that trusts the shim's own bookkeeping
// would pass even if no NSView were ever created. Record counts stay in Elisa's
// retained control arena; these queries are only facts that belong to Cocoa.
int elisa_appkit_subview_count(size_t handle) {
    NSView *container = elisa_container_for(handle);
    return container == nil ? -1 : (int)[[container subviews] count];
}

int elisa_appkit_is_class(size_t handle, size_t class_name) {
    if (handle == 0 || class_name == 0) return 0;
    NSString *name = elisa_appkit_string(class_name);
    if (name == nil) return 0;
    Class wanted = NSClassFromString(name);
    return (wanted != nil && [elisa_appkit_object(handle) isKindOfClass:wanted]) ? 1 : 0;
}

int elisa_appkit_window_is_resizable(size_t handle) {
    id object = elisa_appkit_object(handle);
    if (![object isKindOfClass:[NSWindow class]]) return 0;
    return ([(NSWindow *)object styleMask] & NSWindowStyleMaskResizable) != 0 ? 1 : 0;
}

int elisa_appkit_window_is_floating(size_t handle) {
    id object = elisa_appkit_object(handle);
    if (![object isKindOfClass:[NSWindow class]]) return 0;
    return [object isKindOfClass:[NSPanel class]] &&
           [(NSPanel *)object isFloatingPanel] ? 1 : 0;
}

int elisa_appkit_panel_becomes_key_only(size_t handle) {
    id object = elisa_appkit_object(handle);
    if (![object isKindOfClass:[NSWindow class]] || ![object isKindOfClass:[NSPanel class]]) return 0;
    return [(NSPanel *)object becomesKeyOnlyIfNeeded] ? 1 : 0;
}

int elisa_appkit_button_is_on(size_t handle) {
    NSButton *button = (NSButton *)elisa_appkit_object(handle);
    return [button isKindOfClass:[NSButton class]] && [button state] == NSControlStateValueOn ? 1 : 0;
}

int elisa_appkit_button_bezel_style(size_t handle) {
    id object = elisa_appkit_object(handle);
    if (![object isKindOfClass:[NSButton class]]) return -1;
    return (int)[(NSButton *)object bezelStyle];
}

int elisa_appkit_button_toggles(size_t handle) {
    NSButton *button = (NSButton *)elisa_appkit_object(handle);
    if (![button isKindOfClass:[NSButton class]]) return -1;
    NSControlStateValue before = button.state;
    [button setState:NSControlStateValueOff];
    [button performClick:nil];
    BOOL toggles = button.state == NSControlStateValueOn;
    [button setState:before];
    return toggles ? 1 : 0;
}

int elisa_appkit_scroll_has_vertical(size_t handle) {
    NSScrollView *scroll = (NSScrollView *)elisa_appkit_object(handle);
    if (![scroll isKindOfClass:[NSScrollView class]]) return 0;
    return [scroll hasVerticalScroller] ? 1 : 0;
}

int elisa_appkit_scroll_has_horizontal(size_t handle) {
    NSScrollView *scroll = (NSScrollView *)elisa_appkit_object(handle);
    if (![scroll isKindOfClass:[NSScrollView class]]) return 0;
    return [scroll hasHorizontalScroller] ? 1 : 0;
}

float elisa_appkit_frame_width(size_t handle) {
    id object = elisa_appkit_object(handle);
    if (object == nil) return -1.0f;
    if ([object isKindOfClass:[NSWindow class]]) {
        return (float)[[(NSWindow *)object contentView] frame].size.width;
    }
    return (float)[(NSView *)object frame].size.width;
}

// Is this control's container top-left origin? Asserted directly because
// isFlipped changes how a frame is INTERPRETED, not the value stored in it -- no
// frame comparison can see it, so a test that only checked frames passed happily
// with the whole window upside down.
int elisa_appkit_is_flipped(size_t handle) {
    NSView *container = elisa_container_for(handle);
    return (container != nil && [container isFlipped]) ? 1 : 0;
}

float elisa_appkit_frame_y(size_t handle) {
    id object = elisa_appkit_object(handle);
    if (object == nil) return -1.0f;
    if ([object isKindOfClass:[NSWindow class]]) return 0.0f;
    return (float)[(NSView *)object frame].origin.y;
}

float elisa_appkit_frame_x(size_t handle) {
    id object = elisa_appkit_object(handle);
    if (object == nil) return -1.0f;
    if ([object isKindOfClass:[NSWindow class]]) return 0.0f;
    return (float)[(NSView *)object frame].origin.x;
}

int elisa_appkit_progress_is_indeterminate(size_t handle) {
    NSProgressIndicator *bar = (NSProgressIndicator *)elisa_appkit_object(handle);
    if (![bar isKindOfClass:[NSProgressIndicator class]]) return -1;
    return [bar isIndeterminate] ? 1 : 0;
}

int elisa_appkit_progress_style(size_t handle) {
    NSProgressIndicator *bar = (NSProgressIndicator *)elisa_appkit_object(handle);
    if (![bar isKindOfClass:[NSProgressIndicator class]]) return -1;
    return (int)[bar style];
}
