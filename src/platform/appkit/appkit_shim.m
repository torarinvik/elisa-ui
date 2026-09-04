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

#define ELISA_APPKIT_MAX 256

// A container whose origin is top-left, so a laid-out frame needs no conversion.
@interface ElisaFlippedView : NSView
@end
@implementation ElisaFlippedView
- (BOOL)isFlipped { return elisa_appkit_view_is_flipped() != 0; }
@end

static NSWindow *elisa_window = nil;
static id elisa_objects[ELISA_APPKIT_MAX];
static int elisa_count = 0;

// Resolve a recorded object for headless introspection. Production attachment
// uses the explicit typed attach entry points below; this bookkeeping branch is
// only for read-back checks.
static NSView *elisa_container_for(int index) {
    if (index < 0 || index >= elisa_count) return nil;
    id object = elisa_objects[index];
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
        elisa_count = 0;
        elisa_window = nil;
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
    if (index < 0 || index >= ELISA_APPKIT_MAX) return NO;
    if (index >= elisa_count) elisa_count = index + 1;
    return YES;
}

static void elisa_appkit_store_view(int index, NSView *view) {
    elisa_objects[index] = view;
}

void elisa_appkit_attach_to_window(int index, int parent) {
    if (index < 0 || index >= elisa_count || parent < 0 || parent >= elisa_count) return;
    NSView *view = (NSView *)elisa_objects[index];
    NSView *container = [(NSWindow *)elisa_objects[parent] contentView];
    if (container != nil && view != nil) [container addSubview:view];
}

void elisa_appkit_attach_to_scroll_view(int index, int parent) {
    if (index < 0 || index >= elisa_count || parent < 0 || parent >= elisa_count) return;
    NSView *view = (NSView *)elisa_objects[index];
    NSView *container = [(NSScrollView *)elisa_objects[parent] documentView];
    if (container != nil && view != nil) [container addSubview:view];
}

void elisa_appkit_attach_to_view(int index, int parent) {
    if (index < 0 || index >= elisa_count || parent < 0 || parent >= elisa_count) return;
    NSView *view = (NSView *)elisa_objects[index];
    NSView *container = (NSView *)elisa_objects[parent];
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
        elisa_objects[index] = window;
        elisa_window = window;
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
        elisa_objects[index] = panel;
        elisa_window = panel;
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

void elisa_appkit_create_label(int index) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index)) return;
        elisa_appkit_store_view(index, [NSTextField labelWithString:@""]);
    }
}

void elisa_appkit_create_push_button(int index, int bezel_style) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index)) return;
        NSButton *button = [NSButton buttonWithTitle:@"" target:nil action:nil];
        [button setBezelStyle:(NSBezelStyle)bezel_style];
        elisa_appkit_store_view(index, button);
    }
}

void elisa_appkit_create_toggle_button(int index, int button_type) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index)) return;
        NSButton *button = [NSButton buttonWithTitle:@"" target:nil action:nil];
        [button setButtonType:(NSButtonType)button_type];
        elisa_appkit_store_view(index, button);
    }
}

void elisa_appkit_create_checkbox(int index) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index)) return;
        elisa_appkit_store_view(index, [NSButton checkboxWithTitle:@"" target:nil action:nil]);
    }
}

void elisa_appkit_create_radio_button(int index) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index)) return;
        elisa_appkit_store_view(index, [NSButton radioButtonWithTitle:@"" target:nil action:nil]);
    }
}

void elisa_appkit_create_text_field(int index) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index)) return;
        elisa_appkit_store_view(index, [NSTextField textFieldWithString:@""]);
    }
}

void elisa_appkit_create_slider(int index) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index)) return;
        elisa_appkit_store_view(index, [NSSlider sliderWithValue:0 minValue:0 maxValue:1 target:nil action:nil]);
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
        if (index < 0 || index >= elisa_count) return;
        // A window is positioned by the OS; only its content size is ours.
        [(NSWindow *)elisa_objects[index] setContentSize:NSMakeSize(width, height)];
        [[(NSWindow *)elisa_objects[index] contentView] setFrame:NSMakeRect(0, 0, width, height)];
    }
}

void elisa_appkit_set_view_frame(int index, float x, float y, float width, float height) {
    @autoreleasepool {
        if (index < 0 || index >= elisa_count) return;
        [(NSView *)elisa_objects[index] setFrame:NSMakeRect(x, y, width, height)];
    }
}

// Elisa dispatches this only for a ScrollView. Keeping the document sizing as
// its own typed entry point removes a production policy branch over the
// framework enum from the native object bridge.
void elisa_appkit_set_scroll_document_frame(int index, float width, float height) {
    @autoreleasepool {
        if (index < 0 || index >= elisa_count) return;
        NSScrollView *scroll = (NSScrollView *)elisa_objects[index];
        [[scroll documentView] setFrame:NSMakeRect(0, 0, width, height)];
    }
}

// Elisa creates the counted CFString through CoreFoundation FFI. The shim only
// borrows that opaque object long enough to assign it to the live Cocoa control;
// no UTF-8 policy or byte-to-string conversion remains in this bridge.
void elisa_appkit_set_window_title(int index, size_t text) {
    @autoreleasepool {
        if (index < 0 || index >= elisa_count) return;
        NSString *value = (__bridge NSString *)(void *)text;
        if (value != nil) [(NSWindow *)elisa_objects[index] setTitle:value];
    }
}

void elisa_appkit_set_button_title(int index, size_t text) {
    @autoreleasepool {
        if (index < 0 || index >= elisa_count) return;
        NSString *value = (__bridge NSString *)(void *)text;
        if (value != nil) [(NSButton *)elisa_objects[index] setTitle:value];
    }
}

void elisa_appkit_set_field_text(int index, size_t text) {
    @autoreleasepool {
        if (index < 0 || index >= elisa_count) return;
        NSString *value = (__bridge NSString *)(void *)text;
        if (value != nil) [(NSTextField *)elisa_objects[index] setStringValue:value];
    }
}

void elisa_appkit_set_button_state(int index, int state) {
    @autoreleasepool {
        if (index < 0 || index >= elisa_count) return;
        [(NSButton *)elisa_objects[index] setState:(NSControlStateValue)state];
    }
}

void elisa_appkit_set_slider_state(int index, float low, float high, float value) {
    @autoreleasepool {
        if (index < 0 || index >= elisa_count) return;
        NSSlider *slider = (NSSlider *)elisa_objects[index];
        [slider setMinValue:low];
        [slider setMaxValue:high];
        [slider setDoubleValue:value];
    }
}

void elisa_appkit_set_progress_value(int index, float value) {
    @autoreleasepool {
        if (index < 0 || index >= elisa_count) return;
        [(NSProgressIndicator *)elisa_objects[index] setDoubleValue:value];
    }
}

// Show the window. Separated from the run loop so a headless check can realize a
// tree, assert it, and exit without ever presenting anything.
void elisa_appkit_present(void) {
    @autoreleasepool {
        if (elisa_window == nil) return;
        [elisa_window makeKeyAndOrderFront:nil];
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
// would pass even if no NSView were ever created.
int elisa_appkit_control_count(void) { return elisa_count; }

int elisa_appkit_subview_count(int index) {
    NSView *container = elisa_container_for(index);
    return container == nil ? -1 : (int)[[container subviews] count];
}

int elisa_appkit_is_class(int index, size_t class_name) {
    if (index < 0 || index >= elisa_count || class_name == 0) return 0;
    NSString *name = (__bridge NSString *)(void *)class_name;
    Class wanted = NSClassFromString(name);
    return (wanted != nil && [elisa_objects[index] isKindOfClass:wanted]) ? 1 : 0;
}

int elisa_appkit_window_is_resizable(int index) {
    if (index < 0 || index >= elisa_count || ![elisa_objects[index] isKindOfClass:[NSWindow class]]) return 0;
    return ([(NSWindow *)elisa_objects[index] styleMask] & NSWindowStyleMaskResizable) != 0 ? 1 : 0;
}

int elisa_appkit_window_is_floating(int index) {
    if (index < 0 || index >= elisa_count || ![elisa_objects[index] isKindOfClass:[NSWindow class]]) return 0;
    return [(NSWindow *)elisa_objects[index] isKindOfClass:[NSPanel class]] &&
           [(NSPanel *)elisa_objects[index] isFloatingPanel] ? 1 : 0;
}

int elisa_appkit_panel_becomes_key_only(int index) {
    if (index < 0 || index >= elisa_count || ![elisa_objects[index] isKindOfClass:[NSWindow class]]) return 0;
    if (![elisa_objects[index] isKindOfClass:[NSPanel class]]) return 0;
    return [(NSPanel *)elisa_objects[index] becomesKeyOnlyIfNeeded] ? 1 : 0;
}

int elisa_appkit_button_is_on(int index) {
    if (index < 0 || index >= elisa_count) return 0;
    return [(NSButton *)elisa_objects[index] state] == NSControlStateValueOn ? 1 : 0;
}

int elisa_appkit_button_bezel_style(int index) {
    if (index < 0 || index >= elisa_count) return -1;
    return (int)[(NSButton *)elisa_objects[index] bezelStyle];
}

int elisa_appkit_button_toggles(int index) {
    if (index < 0 || index >= elisa_count) return -1;
    NSButton *button = (NSButton *)elisa_objects[index];
    NSControlStateValue before = button.state;
    [button setState:NSControlStateValueOff];
    [button performClick:nil];
    BOOL toggles = button.state == NSControlStateValueOn;
    [button setState:before];
    return toggles ? 1 : 0;
}

int elisa_appkit_scroll_has_vertical(int index) {
    if (index < 0 || index >= elisa_count || ![elisa_objects[index] isKindOfClass:[NSScrollView class]]) return 0;
    return [(NSScrollView *)elisa_objects[index] hasVerticalScroller] ? 1 : 0;
}

int elisa_appkit_scroll_has_horizontal(int index) {
    if (index < 0 || index >= elisa_count || ![elisa_objects[index] isKindOfClass:[NSScrollView class]]) return 0;
    return [(NSScrollView *)elisa_objects[index] hasHorizontalScroller] ? 1 : 0;
}

float elisa_appkit_frame_width(int index) {
    if (index < 0 || index >= elisa_count) return -1.0f;
    if ([elisa_objects[index] isKindOfClass:[NSWindow class]]) {
        return (float)[[(NSWindow *)elisa_objects[index] contentView] frame].size.width;
    }
    return (float)[(NSView *)elisa_objects[index] frame].size.width;
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
    if (index < 0 || index >= elisa_count) return -1.0f;
    if ([elisa_objects[index] isKindOfClass:[NSWindow class]]) return 0.0f;
    return (float)[(NSView *)elisa_objects[index] frame].origin.y;
}

float elisa_appkit_frame_x(int index) {
    if (index < 0 || index >= elisa_count) return -1.0f;
    if ([elisa_objects[index] isKindOfClass:[NSWindow class]]) return 0.0f;
    return (float)[(NSView *)elisa_objects[index] frame].origin.x;
}

int elisa_appkit_progress_is_indeterminate(int index) {
    if (index < 0 || index >= elisa_count) return -1;
    return [(NSProgressIndicator *)elisa_objects[index] isIndeterminate] ? 1 : 0;
}

int elisa_appkit_progress_style(int index) {
    if (index < 0 || index >= elisa_count) return -1;
    return (int)[(NSProgressIndicator *)elisa_objects[index] style];
}
