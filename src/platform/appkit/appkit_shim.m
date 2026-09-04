// The Objective-C half of the AppKit backend.
//
// WHY A SHIM AND NOT objc_msgSend FROM ELISA. objc_msgSend has no single
// signature -- on arm64 every call must be cast to the exact prototype of the
// method being sent, and getting that wrong is a silent ABI mismatch rather than
// a link error. That cast is a C-language operation. So the Objective-C lives
// here and Elisa sees a flat, typed C API, exactly as it does for SDL3.
//
// This file also owns the index -> NSView* table. ui_controls.elisa's protocol
// hands out dense indices precisely so a backend can keep its own mapping; every
// real toolkit keeps one anyway.
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

static NSMutableDictionary<NSNumber *, id> *elisa_objects = nil;

static id elisa_appkit_object(int index) {
    if (index < 0 || elisa_objects == nil) return nil;
    return elisa_objects[@(index)];
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
static NSView *elisa_container_for(int index) {
    id object = elisa_appkit_object(index);
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
        elisa_objects = [NSMutableDictionary new];
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

// Elisa dispatches the typed control kind before crossing the boundary. The
// shim therefore exposes one native constructor per kind instead of carrying a
// second policy switch over the framework's enum.
static BOOL elisa_appkit_prepare(int index) {
    // Elisa owns the dense index arena and never sends an index outside its
    // validated capacity. The bridge therefore only needs to verify that the
    // opaque object table exists; keeping a second native capacity would let
    // framework state drift between the two layers.
    return index >= 0 && elisa_objects != nil;
}

static void elisa_appkit_store_view(int index, NSView *view) {
    if (elisa_objects == nil || view == nil) return;
    elisa_objects[@(index)] = view;
}

void elisa_appkit_attach_to_window(int index, int parent) {
    NSView *view = (NSView *)elisa_appkit_object(index);
    id object = elisa_appkit_object(parent);
    NSView *container = [object isKindOfClass:[NSWindow class]] ? [(NSWindow *)object contentView] : nil;
    if (container != nil && view != nil) [container addSubview:view];
}

void elisa_appkit_attach_to_scroll_view(int index, int parent) {
    NSView *view = (NSView *)elisa_appkit_object(index);
    id object = elisa_appkit_object(parent);
    NSView *container = [object isKindOfClass:[NSScrollView class]] ? [(NSScrollView *)object documentView] : nil;
    if (container != nil && view != nil) [container addSubview:view];
}

void elisa_appkit_attach_to_view(int index, int parent) {
    NSView *view = (NSView *)elisa_appkit_object(index);
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

void elisa_appkit_create_window_with_style(int index, int style, int backing,
                                           float width, float height) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index)) return;
        NSRect content = NSMakeRect(0, 0, width, height);
        NSWindow *window = [[NSWindow alloc]
            initWithContentRect:content
                      styleMask:(NSWindowStyleMask)style
                        backing:(NSBackingStoreType)backing
                          defer:NO];
        if (window == nil) return;
        [window setContentView:[[ElisaFlippedView alloc] initWithFrame:content]];
        elisa_appkit_store_view(index, (NSView *)window);
    }
}

void elisa_appkit_create_panel_window(int index, int style, int backing,
                                      int floating, int becomes_key_only,
                                      float width, float height) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index)) return;
        NSRect content = NSMakeRect(0, 0, width, height);
        NSPanel *panel = [[NSPanel alloc]
            initWithContentRect:content
                      styleMask:(NSWindowStyleMask)style
                        backing:(NSBackingStoreType)backing
                          defer:NO];
        if (panel == nil) return;
        [panel setFloatingPanel:floating != 0];
        [panel setBecomesKeyOnlyIfNeeded:becomes_key_only != 0];
        [panel setContentView:[[ElisaFlippedView alloc] initWithFrame:content]];
        elisa_appkit_store_view(index, (NSView *)panel);
    }
}

void elisa_appkit_create_panel(int index) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index)) return;
        elisa_appkit_store_view(index, [[ElisaFlippedView alloc] initWithFrame:NSZeroRect]);
    }
}

// The scrollbar policy is resolved by Elisa from the widget axis. The native
// side only constructs the NSScrollView and applies the already-resolved bits.
void elisa_appkit_create_scroll_view(int index, int vertical, int horizontal) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index)) return;
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
        [scroll setHasVerticalScroller:vertical != 0];
        [scroll setHasHorizontalScroller:horizontal != 0];
        [scroll setDocumentView:[[ElisaFlippedView alloc] initWithFrame:NSZeroRect]];
        elisa_appkit_store_view(index, scroll);
    }
}

void elisa_appkit_create_label(int index, size_t text) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index)) return;
        NSString *value = elisa_appkit_string(text);
        if (value == nil) return;
        elisa_appkit_store_view(index, [NSTextField labelWithString:value]);
    }
}

void elisa_appkit_create_push_button(int index, int bezel_style, size_t text) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index)) return;
        NSString *value = elisa_appkit_string(text);
        if (value == nil) return;
        NSButton *button = [NSButton buttonWithTitle:value target:nil action:nil];
        [button setBezelStyle:(NSBezelStyle)bezel_style];
        elisa_appkit_store_view(index, button);
    }
}

void elisa_appkit_create_toggle_button(int index, int button_type, size_t text) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index)) return;
        NSString *value = elisa_appkit_string(text);
        if (value == nil) return;
        NSButton *button = [NSButton buttonWithTitle:value target:nil action:nil];
        [button setButtonType:(NSButtonType)button_type];
        elisa_appkit_store_view(index, button);
    }
}

void elisa_appkit_create_checkbox(int index, size_t text) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index)) return;
        NSString *value = elisa_appkit_string(text);
        if (value == nil) return;
        elisa_appkit_store_view(index, [NSButton checkboxWithTitle:value target:nil action:nil]);
    }
}

void elisa_appkit_create_radio_button(int index, size_t text) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index)) return;
        NSString *value = elisa_appkit_string(text);
        if (value == nil) return;
        elisa_appkit_store_view(index, [NSButton radioButtonWithTitle:value target:nil action:nil]);
    }
}

void elisa_appkit_create_text_field(int index, size_t text) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index)) return;
        NSString *value = elisa_appkit_string(text);
        if (value == nil) return;
        elisa_appkit_store_view(index, [NSTextField textFieldWithString:value]);
    }
}

void elisa_appkit_create_slider(int index, float low, float high, float value) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index)) return;
        elisa_appkit_store_view(index, [NSSlider sliderWithValue:value minValue:low maxValue:high target:nil action:nil]);
    }
}

void elisa_appkit_create_progress_bar(int index, int progress_style, int indeterminate) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index)) return;
        NSProgressIndicator *bar = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
        [bar setStyle:(NSProgressIndicatorStyle)progress_style];
        [bar setIndeterminate:indeterminate != 0];
        elisa_appkit_store_view(index, bar);
    }
}

void elisa_appkit_set_window_frame(int index, float width, float height) {
    @autoreleasepool {
        // A window is positioned by the OS; only its content size is ours.
        NSWindow *window = (NSWindow *)elisa_appkit_object(index);
        if (![window isKindOfClass:[NSWindow class]]) return;
        [window setContentSize:NSMakeSize(width, height)];
        [[window contentView] setFrame:NSMakeRect(0, 0, width, height)];
    }
}

void elisa_appkit_set_view_frame(int index, float x, float y, float width, float height) {
    @autoreleasepool {
        NSView *view = (NSView *)elisa_appkit_object(index);
        if (![view isKindOfClass:[NSView class]]) return;
        [view setFrame:NSMakeRect(x, y, width, height)];
    }
}

// Elisa dispatches this only for a ScrollView. Keeping the document sizing as
// its own typed entry point removes a production policy branch over the
// framework enum from the native object bridge.
void elisa_appkit_set_scroll_document_frame(int index, float width, float height) {
    @autoreleasepool {
        NSScrollView *scroll = (NSScrollView *)elisa_appkit_object(index);
        if (![scroll isKindOfClass:[NSScrollView class]]) return;
        [[scroll documentView] setFrame:NSMakeRect(0, 0, width, height)];
    }
}

// Elisa creates the counted CFString through CoreFoundation FFI. The shim only
// borrows that opaque object long enough to assign it to the live Cocoa control;
// no UTF-8 policy or byte-to-string conversion remains in this bridge.
void elisa_appkit_set_window_title(int index, size_t text) {
    @autoreleasepool {
        NSString *value = elisa_appkit_string(text);
        NSWindow *window = (NSWindow *)elisa_appkit_object(index);
        if (value != nil && [window isKindOfClass:[NSWindow class]]) [window setTitle:value];
    }
}

void elisa_appkit_set_button_title(int index, size_t text) {
    @autoreleasepool {
        NSString *value = elisa_appkit_string(text);
        NSButton *button = (NSButton *)elisa_appkit_object(index);
        if (value != nil && [button isKindOfClass:[NSButton class]]) [button setTitle:value];
    }
}

void elisa_appkit_set_field_text(int index, size_t text) {
    @autoreleasepool {
        NSString *value = elisa_appkit_string(text);
        NSTextField *field = (NSTextField *)elisa_appkit_object(index);
        if (value != nil && [field isKindOfClass:[NSTextField class]]) [field setStringValue:value];
    }
}

void elisa_appkit_set_button_state(int index, int state) {
    @autoreleasepool {
        NSButton *button = (NSButton *)elisa_appkit_object(index);
        if ([button isKindOfClass:[NSButton class]]) [button setState:(NSControlStateValue)state];
    }
}

void elisa_appkit_set_slider_state(int index, float low, float high, float value) {
    @autoreleasepool {
        NSSlider *slider = (NSSlider *)elisa_appkit_object(index);
        if (![slider isKindOfClass:[NSSlider class]]) return;
        [slider setMinValue:low];
        [slider setMaxValue:high];
        [slider setDoubleValue:value];
    }
}

void elisa_appkit_set_progress_value(int index, float value) {
    @autoreleasepool {
        NSProgressIndicator *bar = (NSProgressIndicator *)elisa_appkit_object(index);
        if ([bar isKindOfClass:[NSProgressIndicator class]]) [bar setDoubleValue:value];
    }
}

// Show the window. Separated from the run loop so a headless check can realize a
// tree, assert it, and exit without ever presenting anything.
void elisa_appkit_present(int index) {
    @autoreleasepool {
        NSWindow *window = (NSWindow *)elisa_appkit_object(index);
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
int elisa_appkit_subview_count(int index) {
    NSView *container = elisa_container_for(index);
    return container == nil ? -1 : (int)[[container subviews] count];
}

int elisa_appkit_is_class(int index, size_t class_name) {
    if (index < 0 || class_name == 0) return 0;
    NSString *name = elisa_appkit_string(class_name);
    if (name == nil) return 0;
    Class wanted = NSClassFromString(name);
    return (wanted != nil && [elisa_appkit_object(index) isKindOfClass:wanted]) ? 1 : 0;
}

int elisa_appkit_window_is_resizable(int index) {
    id object = elisa_appkit_object(index);
    if (![object isKindOfClass:[NSWindow class]]) return 0;
    return ([(NSWindow *)object styleMask] & NSWindowStyleMaskResizable) != 0 ? 1 : 0;
}

int elisa_appkit_window_is_floating(int index) {
    id object = elisa_appkit_object(index);
    if (![object isKindOfClass:[NSWindow class]]) return 0;
    return [object isKindOfClass:[NSPanel class]] &&
           [(NSPanel *)object isFloatingPanel] ? 1 : 0;
}

int elisa_appkit_panel_becomes_key_only(int index) {
    id object = elisa_appkit_object(index);
    if (![object isKindOfClass:[NSWindow class]] || ![object isKindOfClass:[NSPanel class]]) return 0;
    return [(NSPanel *)object becomesKeyOnlyIfNeeded] ? 1 : 0;
}

int elisa_appkit_button_is_on(int index) {
    NSButton *button = (NSButton *)elisa_appkit_object(index);
    return [button isKindOfClass:[NSButton class]] && [button state] == NSControlStateValueOn ? 1 : 0;
}

int elisa_appkit_button_bezel_style(int index) {
    id object = elisa_appkit_object(index);
    if (![object isKindOfClass:[NSButton class]]) return -1;
    return (int)[(NSButton *)object bezelStyle];
}

int elisa_appkit_button_toggles(int index) {
    NSButton *button = (NSButton *)elisa_appkit_object(index);
    if (![button isKindOfClass:[NSButton class]]) return -1;
    NSControlStateValue before = button.state;
    [button setState:NSControlStateValueOff];
    [button performClick:nil];
    BOOL toggles = button.state == NSControlStateValueOn;
    [button setState:before];
    return toggles ? 1 : 0;
}

int elisa_appkit_scroll_has_vertical(int index) {
    NSScrollView *scroll = (NSScrollView *)elisa_appkit_object(index);
    if (![scroll isKindOfClass:[NSScrollView class]]) return 0;
    return [scroll hasVerticalScroller] ? 1 : 0;
}

int elisa_appkit_scroll_has_horizontal(int index) {
    NSScrollView *scroll = (NSScrollView *)elisa_appkit_object(index);
    if (![scroll isKindOfClass:[NSScrollView class]]) return 0;
    return [scroll hasHorizontalScroller] ? 1 : 0;
}

float elisa_appkit_frame_width(int index) {
    id object = elisa_appkit_object(index);
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
int elisa_appkit_is_flipped(int index) {
    NSView *container = elisa_container_for(index);
    return (container != nil && [container isFlipped]) ? 1 : 0;
}

float elisa_appkit_frame_y(int index) {
    id object = elisa_appkit_object(index);
    if (object == nil) return -1.0f;
    if ([object isKindOfClass:[NSWindow class]]) return 0.0f;
    return (float)[(NSView *)object frame].origin.y;
}

float elisa_appkit_frame_x(int index) {
    id object = elisa_appkit_object(index);
    if (object == nil) return -1.0f;
    if ([object isKindOfClass:[NSWindow class]]) return 0.0f;
    return (float)[(NSView *)object frame].origin.x;
}

int elisa_appkit_progress_is_indeterminate(int index) {
    NSProgressIndicator *bar = (NSProgressIndicator *)elisa_appkit_object(index);
    if (![bar isKindOfClass:[NSProgressIndicator class]]) return -1;
    return [bar isIndeterminate] ? 1 : 0;
}

int elisa_appkit_progress_style(int index) {
    NSProgressIndicator *bar = (NSProgressIndicator *)elisa_appkit_object(index);
    if (![bar isKindOfClass:[NSProgressIndicator class]]) return -1;
    return (int)[bar style];
}
