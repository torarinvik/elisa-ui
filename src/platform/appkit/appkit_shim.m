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

enum {
    ELISA_APPKIT_WINDOW = 0,
    ELISA_APPKIT_PANEL = 1,
    ELISA_APPKIT_SCROLLVIEW = 2,
    ELISA_APPKIT_LABEL = 3,
    ELISA_APPKIT_PUSHBUTTON = 4,
    ELISA_APPKIT_TOGGLEBUTTON = 5,
    ELISA_APPKIT_CHECKBOX = 6,
    ELISA_APPKIT_RADIOBUTTON = 7,
    ELISA_APPKIT_TEXTFIELD = 8,
    ELISA_APPKIT_SLIDER = 9,
    ELISA_APPKIT_PROGRESSBAR = 10
};

#define ELISA_APPKIT_MAX 256

// A container whose origin is top-left, so a laid-out frame needs no conversion.
@interface ElisaFlippedView : NSView
@end
@implementation ElisaFlippedView
- (BOOL)isFlipped { return YES; }
@end

static NSWindow *elisa_window = nil;
static id elisa_objects[ELISA_APPKIT_MAX];
static int elisa_kinds[ELISA_APPKIT_MAX];
static int elisa_count = 0;

// Resolve a recorded object for headless introspection. Production creation
// receives the parent-is-window fact from Elisa and does not consult this
// bookkeeping branch while attaching children.
static NSView *elisa_container_for(int index) {
    if (index < 0 || index >= elisa_count) return nil;
    id object = elisa_objects[index];
    if (elisa_kinds[index] == ELISA_APPKIT_WINDOW) {
        return [(NSWindow *)object contentView];
    }
    if (elisa_kinds[index] == ELISA_APPKIT_SCROLLVIEW) {
        return [(NSScrollView *)object documentView];
    }
    return (NSView *)object;
}

void elisa_appkit_init(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        elisa_count = 0;
        elisa_window = nil;
    }
}

// Elisa dispatches the typed control kind before crossing the boundary. The
// shim therefore exposes one native constructor per kind instead of carrying a
// second policy switch over the framework's enum.
static BOOL elisa_appkit_prepare(int index, int kind) {
    if (index < 0 || index >= ELISA_APPKIT_MAX) return NO;
    if (index >= elisa_count) elisa_count = index + 1;
    elisa_kinds[index] = kind;
    return YES;
}

static void elisa_appkit_attach(int index, int parent, int parentIsWindow, int parentIsScrollView, NSView *view) {
    elisa_objects[index] = view;
    NSView *container = nil;
    if (parent >= 0 && parent < elisa_count) {
        id object = elisa_objects[parent];
        container = parentIsWindow ? [(NSWindow *)object contentView] :
                    (parentIsScrollView ? [(NSScrollView *)object documentView] : (NSView *)object);
    }
    if (container != nil && view != nil) [container addSubview:view];
}

static void elisa_appkit_create_window_with_style(int index, NSWindowStyleMask style) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index, ELISA_APPKIT_WINDOW)) return;
        NSRect content = NSMakeRect(0, 0, 640, 480);
        NSWindow *window = [[NSWindow alloc]
            initWithContentRect:content
                      styleMask:style
                        backing:NSBackingStoreBuffered
                          defer:NO];
        if (window == nil) return;
        [window setContentView:[[ElisaFlippedView alloc] initWithFrame:content]];
        elisa_objects[index] = window;
        elisa_window = window;
    }
}

void elisa_appkit_create_fixed_window(int index) {
    elisa_appkit_create_window_with_style(index,
        NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable);
}

void elisa_appkit_create_resizable_window(int index) {
    elisa_appkit_create_window_with_style(index,
        NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable |
        NSWindowStyleMaskResizable);
}

void elisa_appkit_create_floating_panel(int index) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index, ELISA_APPKIT_WINDOW)) return;
        NSRect content = NSMakeRect(0, 0, 480, 320);
        NSPanel *panel = [[NSPanel alloc]
            initWithContentRect:content
                      styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                 NSWindowStyleMaskUtilityWindow)
                        backing:NSBackingStoreBuffered
                          defer:NO];
        if (panel == nil) return;
        [panel setFloatingPanel:YES];
        [panel setBecomesKeyOnlyIfNeeded:YES];
        [panel setContentView:[[ElisaFlippedView alloc] initWithFrame:content]];
        elisa_objects[index] = panel;
        elisa_window = panel;
    }
}

void elisa_appkit_create_panel(int index, int parent, int parentIsWindow, int parentIsScrollView) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index, ELISA_APPKIT_PANEL)) return;
        elisa_appkit_attach(index, parent, parentIsWindow, parentIsScrollView, [[ElisaFlippedView alloc] initWithFrame:NSZeroRect]);
    }
}

static void elisa_appkit_create_scroll_view_with_scrollers(int index, int parent,
                                                            int parentIsWindow, int parentIsScrollView,
                                                            BOOL vertical, BOOL horizontal) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index, ELISA_APPKIT_SCROLLVIEW)) return;
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
        [scroll setHasVerticalScroller:vertical];
        [scroll setHasHorizontalScroller:horizontal];
        [scroll setDocumentView:[[ElisaFlippedView alloc] initWithFrame:NSZeroRect]];
        elisa_appkit_attach(index, parent, parentIsWindow, parentIsScrollView, scroll);
    }
}

void elisa_appkit_create_vertical_scroll_view(int index, int parent, int parentIsWindow, int parentIsScrollView) {
    elisa_appkit_create_scroll_view_with_scrollers(index, parent, parentIsWindow, parentIsScrollView, YES, NO);
}

void elisa_appkit_create_horizontal_scroll_view(int index, int parent, int parentIsWindow, int parentIsScrollView) {
    elisa_appkit_create_scroll_view_with_scrollers(index, parent, parentIsWindow, parentIsScrollView, NO, YES);
}

void elisa_appkit_create_label(int index, int parent, int parentIsWindow, int parentIsScrollView) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index, ELISA_APPKIT_LABEL)) return;
        elisa_appkit_attach(index, parent, parentIsWindow, parentIsScrollView, [NSTextField labelWithString:@""]);
    }
}

void elisa_appkit_create_push_button(int index, int parent, int parentIsWindow, int parentIsScrollView) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index, ELISA_APPKIT_PUSHBUTTON)) return;
        NSButton *button = [NSButton buttonWithTitle:@"" target:nil action:nil];
        [button setBezelStyle:NSBezelStyleRounded];
        elisa_appkit_attach(index, parent, parentIsWindow, parentIsScrollView, button);
    }
}

void elisa_appkit_create_toggle_button(int index, int parent, int parentIsWindow, int parentIsScrollView) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index, ELISA_APPKIT_TOGGLEBUTTON)) return;
        NSButton *button = [NSButton buttonWithTitle:@"" target:nil action:nil];
        [button setButtonType:NSButtonTypePushOnPushOff];
        elisa_appkit_attach(index, parent, parentIsWindow, parentIsScrollView, button);
    }
}

void elisa_appkit_create_checkbox(int index, int parent, int parentIsWindow, int parentIsScrollView) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index, ELISA_APPKIT_CHECKBOX)) return;
        elisa_appkit_attach(index, parent, parentIsWindow, parentIsScrollView, [NSButton checkboxWithTitle:@"" target:nil action:nil]);
    }
}

void elisa_appkit_create_radio_button(int index, int parent, int parentIsWindow, int parentIsScrollView) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index, ELISA_APPKIT_RADIOBUTTON)) return;
        elisa_appkit_attach(index, parent, parentIsWindow, parentIsScrollView, [NSButton radioButtonWithTitle:@"" target:nil action:nil]);
    }
}

void elisa_appkit_create_text_field(int index, int parent, int parentIsWindow, int parentIsScrollView) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index, ELISA_APPKIT_TEXTFIELD)) return;
        elisa_appkit_attach(index, parent, parentIsWindow, parentIsScrollView, [NSTextField textFieldWithString:@""]);
    }
}

void elisa_appkit_create_slider(int index, int parent, int parentIsWindow, int parentIsScrollView) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index, ELISA_APPKIT_SLIDER)) return;
        elisa_appkit_attach(index, parent, parentIsWindow, parentIsScrollView, [NSSlider sliderWithValue:0 minValue:0 maxValue:1 target:nil action:nil]);
    }
}

void elisa_appkit_create_progress_bar(int index, int parent, int parentIsWindow, int parentIsScrollView) {
    @autoreleasepool {
        if (!elisa_appkit_prepare(index, ELISA_APPKIT_PROGRESSBAR)) return;
        NSProgressIndicator *bar = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
        [bar setStyle:NSProgressIndicatorStyleBar];
        [bar setIndeterminate:NO];
        elisa_appkit_attach(index, parent, parentIsWindow, parentIsScrollView, bar);
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

static NSString *elisa_appkit_string(const char *text, size_t length) {
    if (text == NULL) return nil;
    return [[NSString alloc] initWithBytes:text length:length encoding:NSUTF8StringEncoding];
}

void elisa_appkit_set_window_title(int index, const char *text, size_t length) {
    @autoreleasepool {
        if (index < 0 || index >= elisa_count) return;
        NSString *value = elisa_appkit_string(text, length);
        if (value != nil) [(NSWindow *)elisa_objects[index] setTitle:value];
    }
}

void elisa_appkit_set_button_title(int index, const char *text, size_t length) {
    @autoreleasepool {
        if (index < 0 || index >= elisa_count) return;
        NSString *value = elisa_appkit_string(text, length);
        if (value != nil) [(NSButton *)elisa_objects[index] setTitle:value];
    }
}

void elisa_appkit_set_field_text(int index, const char *text, size_t length) {
    @autoreleasepool {
        if (index < 0 || index >= elisa_count) return;
        NSString *value = elisa_appkit_string(text, length);
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

int elisa_appkit_is_class(int index, const char *class_name) {
    if (index < 0 || index >= elisa_count || class_name == NULL) return 0;
    Class wanted = NSClassFromString([NSString stringWithUTF8String:class_name]);
    return (wanted != nil && [elisa_objects[index] isKindOfClass:wanted]) ? 1 : 0;
}

int elisa_appkit_window_is_resizable(int index) {
    if (index < 0 || index >= elisa_count || elisa_kinds[index] != ELISA_APPKIT_WINDOW) return 0;
    return ([(NSWindow *)elisa_objects[index] styleMask] & NSWindowStyleMaskResizable) != 0 ? 1 : 0;
}

int elisa_appkit_window_is_floating(int index) {
    if (index < 0 || index >= elisa_count || elisa_kinds[index] != ELISA_APPKIT_WINDOW) return 0;
    return [(NSWindow *)elisa_objects[index] isKindOfClass:[NSPanel class]] &&
           [(NSPanel *)elisa_objects[index] isFloatingPanel] ? 1 : 0;
}

int elisa_appkit_button_is_on(int index) {
    if (index < 0 || index >= elisa_count) return 0;
    return [(NSButton *)elisa_objects[index] state] == NSControlStateValueOn ? 1 : 0;
}

int elisa_appkit_scroll_has_vertical(int index) {
    if (index < 0 || index >= elisa_count || elisa_kinds[index] != ELISA_APPKIT_SCROLLVIEW) return 0;
    return [(NSScrollView *)elisa_objects[index] hasVerticalScroller] ? 1 : 0;
}

int elisa_appkit_scroll_has_horizontal(int index) {
    if (index < 0 || index >= elisa_count || elisa_kinds[index] != ELISA_APPKIT_SCROLLVIEW) return 0;
    return [(NSScrollView *)elisa_objects[index] hasHorizontalScroller] ? 1 : 0;
}

float elisa_appkit_frame_width(int index) {
    if (index < 0 || index >= elisa_count) return -1.0f;
    if (elisa_kinds[index] == ELISA_APPKIT_WINDOW) {
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
    if (elisa_kinds[index] == ELISA_APPKIT_WINDOW) return 0.0f;
    return (float)[(NSView *)elisa_objects[index] frame].origin.y;
}

float elisa_appkit_frame_x(int index) {
    if (index < 0 || index >= elisa_count) return -1.0f;
    if (elisa_kinds[index] == ELISA_APPKIT_WINDOW) return 0.0f;
    return (float)[(NSView *)elisa_objects[index] frame].origin.x;
}
