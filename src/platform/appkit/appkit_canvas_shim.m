// AppKit host for elisa-ui's CUSTOM-PAINTED backend.
//
// AppKit owns the window, event queue and CoreGraphics context. Elisa owns the
// widget tree and emits UiCore::Command values; drawRect calls back into Elisa
// to replay that command batch into the current context.

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

extern void elisa_appkit_canvas_frame(size_t context);
extern void elisa_appkit_canvas_resize(float width, float height);
extern size_t elisa_appkit_canvas_pointer_move_event(float x, float y);
extern void elisa_appkit_canvas_pointer_button(float x, float y, int button, int down, int clickCount);
extern void elisa_appkit_canvas_pointer_scroll(float x, float y, float dx, float dy);
extern void elisa_appkit_canvas_raw_key(int down, int keyCode, int character);
extern void elisa_appkit_canvas_raw_flags(int keyCode, size_t modifiers);
extern void elisa_appkit_canvas_focus_changed(int focused);
extern void elisa_appkit_canvas_accessibility_environment_changed(void);
extern void elisa_appkit_canvas_window_closed(void);
extern void elisa_appkit_canvas_key_down_event(size_t event, int keyCode, size_t character, size_t modifiers);
extern void elisa_appkit_canvas_key_up(int keyCode, size_t character);
extern int elisa_appkit_canvas_accessibility_activate(size_t index);
extern int elisa_appkit_canvas_accessibility_adjust(size_t index, int direction);
extern int elisa_appkit_canvas_pointer_button_primary(void);
extern int elisa_appkit_canvas_pointer_button_secondary(void);
extern int elisa_appkit_canvas_accessibility_increment_direction(void);
extern int elisa_appkit_canvas_accessibility_decrement_direction(void);
extern size_t elisa_appkit_canvas_accessibility_capacity(void);
extern int elisa_appkit_canvas_accepts_text(void);
extern size_t elisa_appkit_canvas_not_found(void);
extern int elisa_appkit_canvas_has_marked_text(void);
extern size_t elisa_appkit_canvas_pointer_leave_event(void);
extern void elisa_appkit_canvas_set_text(size_t index, size_t text);
extern size_t elisa_appkit_canvas_selection_location(void);
extern size_t elisa_appkit_canvas_selection_length(void);
extern void elisa_appkit_canvas_set_selected_range(size_t index, size_t location, size_t length);
extern size_t elisa_appkit_canvas_marked_location(void);
extern size_t elisa_appkit_canvas_marked_length(void);
extern void elisa_appkit_canvas_commit_text(size_t text,
                                            size_t replacementLocation, size_t replacementLength);
extern void elisa_appkit_canvas_update_marked_text(size_t text,
                                                   size_t selectedLocation, size_t selectedLength,
                                                   size_t replacementLocation, size_t replacementLength);
extern void elisa_appkit_canvas_unmark_text(void);
extern void elisa_appkit_canvas_text_selector_handle(size_t selector);
extern int elisa_appkit_canvas_text_action_handle(size_t selector);
extern int elisa_appkit_canvas_text_action_enabled(int action);
extern int elisa_appkit_canvas_text_action_valid(int action);
extern int elisa_appkit_canvas_perform_text_action(int action);
extern float elisa_appkit_canvas_character_x(size_t location);
extern float elisa_appkit_canvas_caret_width(void);
extern float elisa_appkit_canvas_caret_y(void);
extern float elisa_appkit_canvas_caret_height(void);
extern size_t elisa_appkit_canvas_character_at_x(float x);
extern size_t elisa_appkit_canvas_range_location(size_t location);
extern size_t elisa_appkit_canvas_range_length(size_t location, size_t length);
extern size_t elisa_appkit_canvas_range_string(size_t location, size_t length);
extern int elisa_appkit_canvas_view_is_flipped(void);
extern int elisa_appkit_canvas_view_accepts_first_responder(void);
extern int elisa_appkit_canvas_view_is_accessibility_element(void);
extern size_t elisa_appkit_canvas_tracking_options(void);

@class ElisaCanvasView;
@class ElisaAccessibilityElement;
// An unpresented headless window is not reliably retained by its content view;
// keep this owning reference until Cocoa takes over the visible window.
static NSWindow *elisa_canvas_window;
static ElisaCanvasView *elisa_canvas_view;
static NSMutableArray *elisa_accessibility_children;

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

@interface ElisaAccessibilityElement : NSAccessibilityElement
@property(nonatomic) size_t elisaIndex;
@property(nonatomic) size_t elisaIdentifier;
@property(nonatomic, strong) NSCursor *elisaCursor;
@property(nonatomic) BOOL elisaSynchronizing;
@property(nonatomic) NSRect elisaLocalFrame;
@end
@implementation ElisaAccessibilityElement
- (BOOL)accessibilityPerformPress {
    return elisa_appkit_canvas_accessibility_activate(self.elisaIndex) != 0;
}
- (BOOL)accessibilityPerformIncrement {
    return elisa_appkit_canvas_accessibility_adjust(self.elisaIndex,
        elisa_appkit_canvas_accessibility_increment_direction()) != 0;
}
- (BOOL)accessibilityPerformDecrement {
    return elisa_appkit_canvas_accessibility_adjust(self.elisaIndex,
        elisa_appkit_canvas_accessibility_decrement_direction()) != 0;
}
- (void)setAccessibilityValue:(id)value {
    [super setAccessibilityValue:value];
    if (self.elisaSynchronizing || ![value isKindOfClass:[NSString class]]) return;
    elisa_appkit_canvas_set_text(self.elisaIndex, (size_t)(__bridge void *)value);
}
- (void)setAccessibilitySelectedTextRange:(NSRange)value {
    [super setAccessibilitySelectedTextRange:value];
    if (self.elisaSynchronizing) return;
    elisa_appkit_canvas_set_selected_range(self.elisaIndex, value.location, value.length);
}
- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag
             point:(NSPoint)point userData:(void *)data {
    (void)view; (void)tag; (void)point; (void)data;
    return self.accessibilityHelp;
}
@end

@interface ElisaCanvasView : NSView <NSTextInputClient, NSUserInterfaceValidations>
@end

static NSWindow *elisa_appkit_canvas_window(void) {
    if (elisa_canvas_window != nil) return elisa_canvas_window;
    return elisa_canvas_view == nil ? nil : [elisa_canvas_view window];
}

// FFI strings are borrowed opaque Objective-C objects. Validate their dynamic
// type once at the boundary so a non-string handle cannot reach an NSString
// initializer, menu setter, or pasteboard API.
static NSString *elisa_appkit_canvas_string(size_t handle) {
    if (handle == 0) return nil;
    id object = (__bridge id)(void *)handle;
    return [object isKindOfClass:[NSString class]] ? object : nil;
}

// NSTextInputClient permits either NSString or NSAttributedString for edited
// text. Keep that protocol adaptation typed here; an unrelated object must not
// be reinterpreted as an NSString and sent across the FFI.
static NSString *elisa_appkit_canvas_input_string(id input) {
    if ([input isKindOfClass:[NSAttributedString class]]) return [(NSAttributedString *)input string];
    return [input isKindOfClass:[NSString class]] ? input : nil;
}

static NSCursor *elisa_appkit_canvas_cursor(size_t handle) {
    if (handle == 0) return nil;
    id object = (__bridge id)(void *)handle;
    return [object isKindOfClass:[NSCursor class]] ? object : nil;
}

// Key interpretation receives a borrowed NSEvent handle from the view's
// callback. Validate it before placing it in an NSArray and handing it back to
// AppKit; malformed cross-boundary data must be a no-op, never an Objective-C
// message to an arbitrary object.
static NSEvent *elisa_appkit_canvas_event(size_t handle) {
    if (handle == 0) return nil;
    id object = (__bridge id)(void *)handle;
    return [object isKindOfClass:[NSEvent class]] ? object : nil;
}

@interface ElisaCanvasDelegate : NSObject <NSWindowDelegate>
@end
@implementation ElisaCanvasDelegate
- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    elisa_appkit_canvas_window_closed();
}
- (void)windowDidResignKey:(NSNotification *)notification {
    (void)notification;
    elisa_appkit_canvas_focus_changed(0);
}
- (void)windowDidBecomeKey:(NSNotification *)notification {
    (void)notification;
    elisa_appkit_canvas_focus_changed(1);
}
- (void)windowDidMove:(NSNotification *)notification {
    (void)notification;
    elisa_appkit_canvas_accessibility_environment_changed();
}
- (void)windowDidChangeBackingProperties:(NSNotification *)notification {
    (void)notification;
    elisa_appkit_canvas_accessibility_environment_changed();
}
@end
static ElisaCanvasDelegate *elisa_canvas_delegate;

void elisa_appkit_canvas_interpret_key_event(size_t event) {
    NSEvent *nativeEvent = elisa_appkit_canvas_event(event);
    if (nativeEvent != nil && elisa_canvas_view != nil) [elisa_canvas_view interpretKeyEvents:@[nativeEvent]];
}

@implementation ElisaCanvasView
- (BOOL)isFlipped { return elisa_appkit_canvas_view_is_flipped() != 0; }
- (BOOL)acceptsFirstResponder { return elisa_appkit_canvas_view_accepts_first_responder() != 0; }
- (BOOL)isAccessibilityElement { return elisa_appkit_canvas_view_is_accessibility_element() != 0; }
- (NSArray *)accessibilityChildren { return elisa_accessibility_children ?: @[]; }
- (NSArray *)accessibilityChildrenInNavigationOrder { return elisa_accessibility_children ?: @[]; }
- (NSTrackingAreaOptions)trackingOptions {
    return (NSTrackingAreaOptions)elisa_appkit_canvas_tracking_options();
}
- (void)updateTrackingAreas {
    for (NSTrackingArea *area in [self trackingAreas]) [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:[self trackingOptions] owner:self userInfo:nil]];
    [super updateTrackingAreas];
}
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    CGContextRef context = [[NSGraphicsContext currentContext] CGContext];
    CGContextSaveGState(context);
    elisa_appkit_canvas_frame((size_t)context);
    CGContextRestoreGState(context);
}
- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    elisa_appkit_canvas_resize(size.width, size.height);
}
- (NSPoint)eventPoint:(NSEvent *)event {
    return [self convertPoint:[event locationInWindow] fromView:nil];
}
- (void)resetCursorRects {
    [super resetCursorRects];
    for (ElisaAccessibilityElement *element in elisa_accessibility_children) {
        if (element.elisaCursor != nil) [self addCursorRect:element.elisaLocalFrame cursor:element.elisaCursor];
    }
}
- (void)forwardMouseButton:(NSEvent *)event down:(BOOL)down button:(int)button {
    NSPoint p = [self eventPoint:event];
    // The native view reports raw button facts. Elisa decides which framework
    // events a press/release produces and preserves the press-side text-click
    // ordering; this adapter only supplies Cocoa's coordinate and click data.
    elisa_appkit_canvas_pointer_button(p.x, p.y, button, down, (int)event.clickCount);
}
- (void)mouseMoved:(NSEvent *)event {
    NSPoint p = [self eventPoint:event];
    NSCursor *nativeCursor = elisa_appkit_canvas_cursor(elisa_appkit_canvas_pointer_move_event(p.x, p.y));
    if (nativeCursor != nil) [nativeCursor set];
}
- (void)mouseDragged:(NSEvent *)event { [self mouseMoved:event]; }
- (void)rightMouseDragged:(NSEvent *)event { [self mouseMoved:event]; }
- (void)otherMouseDragged:(NSEvent *)event { [self mouseMoved:event]; }
- (void)mouseDown:(NSEvent *)event { [self forwardMouseButton:event down:YES button:elisa_appkit_canvas_pointer_button_primary()]; }
- (void)rightMouseDown:(NSEvent *)event { [self forwardMouseButton:event down:YES button:elisa_appkit_canvas_pointer_button_secondary()]; }
- (void)otherMouseDown:(NSEvent *)event { [self forwardMouseButton:event down:YES button:(int)event.buttonNumber]; }
- (void)mouseUp:(NSEvent *)event { [self forwardMouseButton:event down:NO button:elisa_appkit_canvas_pointer_button_primary()]; }
- (void)rightMouseUp:(NSEvent *)event { [self forwardMouseButton:event down:NO button:elisa_appkit_canvas_pointer_button_secondary()]; }
- (void)otherMouseUp:(NSEvent *)event { [self forwardMouseButton:event down:NO button:(int)event.buttonNumber]; }
- (void)mouseExited:(NSEvent *)event {
    (void)event;
    NSCursor *cursor = elisa_appkit_canvas_cursor(elisa_appkit_canvas_pointer_leave_event());
    if (cursor != nil) [cursor set];
}
- (void)scrollWheel:(NSEvent *)event { NSPoint p=[self eventPoint:event]; elisa_appkit_canvas_pointer_scroll(p.x,p.y,[event scrollingDeltaX],[event scrollingDeltaY]); }
- (void)keyDown:(NSEvent *)event {
    NSString *chars = [event charactersIgnoringModifiers];
    elisa_appkit_canvas_key_down_event((size_t)(__bridge void *)event, event.keyCode,
                                       (size_t)(__bridge void *)chars, (size_t)[event modifierFlags]);
}
- (void)keyUp:(NSEvent *)event {
    NSString *chars = [event charactersIgnoringModifiers];
    elisa_appkit_canvas_key_up(event.keyCode, (size_t)(__bridge void *)chars);
}
- (void)insertText:(id)input replacementRange:(NSRange)replacementRange {
    NSString *text = elisa_appkit_canvas_input_string(input);
    if (text == nil) return;
    elisa_appkit_canvas_commit_text((size_t)(__bridge void *)text,
                                    replacementRange.location, replacementRange.length);
}
- (void)doCommandBySelector:(SEL)selector {
    elisa_appkit_canvas_text_selector_handle((size_t)(void *)selector);
}
- (void)selectAll:(id)sender {
    (void)sender;
    int action = elisa_appkit_canvas_text_action_handle((size_t)(void *)_cmd);
    if (action != 0) (void)elisa_appkit_canvas_perform_text_action(action);
}
- (void)undo:(id)sender {
    (void)sender;
    int action = elisa_appkit_canvas_text_action_handle((size_t)(void *)_cmd);
    if (action != 0) (void)elisa_appkit_canvas_perform_text_action(action);
}
- (void)redo:(id)sender {
    (void)sender;
    int action = elisa_appkit_canvas_text_action_handle((size_t)(void *)_cmd);
    if (action != 0) (void)elisa_appkit_canvas_perform_text_action(action);
}
- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
    int action = elisa_appkit_canvas_text_action_handle((size_t)(void *)item.action);
    return elisa_appkit_canvas_text_action_valid(action) != 0;
}
- (void)copy:(id)sender {
    (void)sender;
    int action = elisa_appkit_canvas_text_action_handle((size_t)(void *)_cmd);
    if (action != 0) (void)elisa_appkit_canvas_perform_text_action(action);
}
- (void)cut:(id)sender {
    (void)sender;
    int action = elisa_appkit_canvas_text_action_handle((size_t)(void *)_cmd);
    if (action != 0) (void)elisa_appkit_canvas_perform_text_action(action);
}
- (void)paste:(id)sender {
    (void)sender;
    int action = elisa_appkit_canvas_text_action_handle((size_t)(void *)_cmd);
    if (action != 0) (void)elisa_appkit_canvas_perform_text_action(action);
}
- (BOOL)hasMarkedText { return elisa_appkit_canvas_has_marked_text() != 0; }
- (NSRange)markedRange {
    return NSMakeRange(elisa_appkit_canvas_marked_location(),
                       elisa_appkit_canvas_marked_length());
}
- (NSRange)selectedRange {
    return NSMakeRange(elisa_appkit_canvas_selection_location(),
                       elisa_appkit_canvas_selection_length());
}
- (void)setMarkedText:(id)text selectedRange:(NSRange)selectedRange replacementRange:(NSRange)replacementRange {
    NSString *plain = elisa_appkit_canvas_input_string(text);
    if (plain == nil) return;
    elisa_appkit_canvas_update_marked_text((size_t)(__bridge void *)plain,
                                           selectedRange.location, selectedRange.length,
                                           replacementRange.location, replacementRange.length);
}
- (void)unmarkText { elisa_appkit_canvas_unmark_text(); }
- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText { return @[]; }
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
    size_t native = elisa_appkit_canvas_range_string(range.location, range.length);
    if (native == 0) return nil;
    NSRange safe = NSMakeRange(elisa_appkit_canvas_range_location(range.location),
                               elisa_appkit_canvas_range_length(range.location, range.length));
    if (actualRange != NULL) *actualRange = safe;
    NSString *text = elisa_appkit_canvas_string(native);
    if (text == nil) return nil;
    NSAttributedString *result = [[NSAttributedString alloc] initWithString:text];
    CFRelease((CFTypeRef)(void *)native);
    return result;
}
- (NSUInteger)characterIndexForPoint:(NSPoint)point {
    if (self.window == nil) return elisa_appkit_canvas_not_found();
    NSPoint inWindow = [self.window convertPointFromScreen:point];
    NSPoint local = [self convertPoint:inWindow fromView:nil];
    return elisa_appkit_canvas_character_at_x(local.x);
}
- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
    if (!elisa_appkit_canvas_accepts_text() || self.window == nil) {
        if (actualRange != NULL) *actualRange = NSMakeRange(elisa_appkit_canvas_not_found(), 0);
        return NSZeroRect;
    }
    size_t location = elisa_appkit_canvas_range_location(range.location);
    size_t length = elisa_appkit_canvas_range_length(range.location, range.length);
    if (actualRange != NULL) *actualRange = NSMakeRange(location, length);
    NSRect local = NSMakeRect(elisa_appkit_canvas_character_x(location), elisa_appkit_canvas_caret_y(),
                              elisa_appkit_canvas_caret_width(), elisa_appkit_canvas_caret_height());
    NSRect inWindow = [self convertRect:local toView:nil];
    return [self.window convertRectToScreen:inWindow];
}
- (void)flagsChanged:(NSEvent *)event {
    elisa_appkit_canvas_raw_flags(event.keyCode, (size_t)[event modifierFlags]);
}
@end

// Cocoa style masks are exported as facts so Elisa can assemble window policy
// without copying SDK ordinals into the retained backend.
int elisa_appkit_canvas_window_style_titled(void) {
    return (int)NSWindowStyleMaskTitled;
}

int elisa_appkit_canvas_window_style_closable(void) {
    return (int)NSWindowStyleMaskClosable;
}

int elisa_appkit_canvas_window_style_miniaturizable(void) {
    return (int)NSWindowStyleMaskMiniaturizable;
}

int elisa_appkit_canvas_window_style_resizable(void) {
    return (int)NSWindowStyleMaskResizable;
}

int elisa_appkit_canvas_backing_store_buffered(void) {
    return (int)NSBackingStoreBuffered;
}

size_t elisa_appkit_canvas_pasteboard_type_string(void) {
    return (size_t)(__bridge void *)NSPasteboardTypeString;
}

size_t elisa_appkit_canvas_bitmap_color_space_calibrated_rgb(void) {
    return (size_t)(__bridge void *)NSCalibratedRGBColorSpace;
}

int elisa_appkit_canvas_bitmap_file_type_png(void) {
    return (int)NSBitmapImageFileTypePNG;
}

int elisa_appkit_canvas_activation_policy_regular(void) {
    return (int)NSApplicationActivationPolicyRegular;
}

int elisa_appkit_canvas_activation_policy_prohibited(void) {
    return (int)NSApplicationActivationPolicyProhibited;
}

int elisa_appkit_canvas_tabbing_mode_preferred(void) {
    return (int)NSWindowTabbingModePreferred;
}

int elisa_appkit_canvas_tabbing_mode_disallowed(void) {
    return (int)NSWindowTabbingModeDisallowed;
}

size_t elisa_appkit_canvas_tracking_mouse_moved(void) {
    return (size_t)NSTrackingMouseMoved;
}

size_t elisa_appkit_canvas_tracking_mouse_entered_exited(void) {
    return (size_t)NSTrackingMouseEnteredAndExited;
}

size_t elisa_appkit_canvas_tracking_active_in_key_window(void) {
    return (size_t)NSTrackingActiveInKeyWindow;
}

size_t elisa_appkit_canvas_tracking_in_visible_rect(void) {
    return (size_t)NSTrackingInVisibleRect;
}

size_t elisa_appkit_canvas_run_loop_common_modes(void) {
    return (size_t)(__bridge void *)NSRunLoopCommonModes;
}

// NSNotFound is a platform sentinel used by NSTextInputClient. Export the
// native value as a fact; Elisa owns every decision about how that sentinel
// affects selection and text editing.
size_t elisa_appkit_canvas_not_found(void) {
    return NSNotFound;
}

// The notification name is an exported Cocoa object, not framework policy.
// Elisa decides when a layout changed and passes this opaque identity back
// through the FFI so the bridge only performs NSAccessibilityPostNotification.
size_t elisa_appkit_canvas_accessibility_layout_changed_notification(void) {
    return (size_t)(__bridge void *)NSAccessibilityLayoutChangedNotification;
}

// The window title arrives as an opaque, counted CFString created by Elisa.
// Cocoa retains/copies it through -setTitle; the bridge does not perform any
// UTF-8 decoding itself.
int elisa_appkit_canvas_open(size_t title, float width, float height,
                             int style, int backing) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSRect rect = NSMakeRect(0, 0, width, height);
        NSWindowStyleMask styleMask = (NSWindowStyleMask)style;
        NSWindow *window = [[NSWindow alloc] initWithContentRect:rect
            styleMask:styleMask
            backing:(NSBackingStoreType)backing defer:NO];
        if (window == nil) return 0;
        NSString *name = title == 0 ? nil : elisa_appkit_canvas_string(title);
        if (title != 0 && name == nil) return 0;
        if (name != nil) [window setTitle:name];
        // View construction may synchronously report its initial frame. The
        // Elisa adapter owns the readiness guard and filters that callback
        // until app_init has completed.
        elisa_canvas_view = [[ElisaCanvasView alloc] initWithFrame:rect];
        elisa_accessibility_children = [NSMutableArray new];
        elisa_canvas_window = window;
        elisa_canvas_delegate = [ElisaCanvasDelegate new];
        [window setDelegate:elisa_canvas_delegate];
        [window setContentView:elisa_canvas_view];
        return 1;
    }
}

void elisa_appkit_canvas_set_activation_policy(int policy) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:(NSApplicationActivationPolicy)policy];
    }
}

void elisa_appkit_canvas_focus(void) {
    NSWindow *window = elisa_appkit_canvas_window();
    if (window != nil && elisa_canvas_view != nil) {
        [window makeFirstResponder:elisa_canvas_view];
    }
}

void elisa_appkit_canvas_set_tabbing_mode(int mode) {
    NSWindow *window = elisa_appkit_canvas_window();
    if (window != nil) {
        [window setTabbingMode:(NSWindowTabbingMode)mode];
    }
}

void elisa_appkit_canvas_set_restorable(int restorable) {
    NSWindow *window = elisa_appkit_canvas_window();
    if (window != nil) {
        [window setRestorable:restorable != 0];
    }
}

void elisa_appkit_canvas_center(void) {
    NSWindow *window = elisa_appkit_canvas_window();
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
    item.keyEquivalentModifierMask = (NSEventModifierFlags)modifiers;
}

void elisa_appkit_canvas_menu_add_item(size_t menu, size_t title,
                                        size_t keyEquivalent, size_t actionHandle,
                                        size_t modifiers) {
    NSString *value = elisa_appkit_canvas_string(title);
    NSString *key = elisa_appkit_canvas_string(keyEquivalent);
    elisa_appkit_canvas_menu_add_item_title(menu, value, key, actionHandle, modifiers);
}

size_t elisa_appkit_canvas_modifier_command(void) { return NSEventModifierFlagCommand; }
size_t elisa_appkit_canvas_modifier_shift(void) { return NSEventModifierFlagShift; }
size_t elisa_appkit_canvas_modifier_option(void) { return NSEventModifierFlagOption; }
size_t elisa_appkit_canvas_modifier_control(void) { return NSEventModifierFlagControl; }
size_t elisa_appkit_canvas_modifier_device_independent_mask(void) {
    return NSEventModifierFlagDeviceIndependentFlagsMask;
}

void elisa_appkit_canvas_menu_add_separator(size_t menu) {
    NSMenu *value = (__bridge NSMenu *)(void *)menu;
    if (![value isKindOfClass:[NSMenu class]]) return;
    [value addItem:[NSMenuItem separatorItem]];
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

size_t elisa_appkit_canvas_schedule_redraw(float delay, size_t run_loop_mode) {
    NSString *mode = elisa_appkit_canvas_string(run_loop_mode);
    if (mode == nil) return 0;
    NSTimer *timer = [NSTimer timerWithTimeInterval:delay repeats:NO block:^(NSTimer *fired) {
        (void)fired;
        [elisa_canvas_view setNeedsDisplay:YES];
    }];
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

void elisa_appkit_canvas_set_min_size(float width, float height) {
    NSWindow *window = elisa_appkit_canvas_window();
    if (window != nil) [window setContentMinSize:NSMakeSize(width, height)];
}

int elisa_appkit_canvas_present(void) {
    NSWindow *window = elisa_appkit_canvas_window();
    if (window == nil || elisa_canvas_view == nil) return 0;
    [window makeKeyAndOrderFront:nil];
    return 1;
}

void elisa_appkit_canvas_activate(void) {
    [NSApp activateIgnoringOtherApps:YES];
}
// Snapshot paths are borrowed opaque CFStrings created by Elisa. The native
// side only asks Cocoa to encode the bitmap and write it to that path.
int elisa_appkit_canvas_present_headless(size_t color_space, int image_type,
                                         size_t snapshot, int pixels_width,
                                         int pixels_height, int bits_per_sample,
                                         int samples_per_pixel, int has_alpha,
                                         int bitmap_format) {
    // Exercise the real frame, painter and semantic bridge without ordering
    // a window onscreen or stealing focus from the user's current app.
    if (elisa_canvas_view == nil) return 0;
    NSRect bounds = elisa_canvas_view.bounds;
    if (pixels_width <= 0 || pixels_height <= 0) return 0;
    NSString *colorSpace = elisa_appkit_canvas_string(color_space);
    if (colorSpace == nil) return 0;
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
        pixelsWide:(NSUInteger)pixels_width
        pixelsHigh:(NSUInteger)pixels_height
        bitsPerSample:(NSInteger)bits_per_sample
        samplesPerPixel:(NSInteger)samples_per_pixel
        hasAlpha:has_alpha != 0 isPlanar:NO
        colorSpaceName:colorSpace
        bitmapFormat:(NSBitmapFormat)bitmap_format bytesPerRow:0 bitsPerPixel:0];
    if (bitmap == nil) return 0;
    NSGraphicsContext *graphics = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    if (graphics == nil) return 0;
    [elisa_canvas_view displayRectIgnoringOpacity:bounds inContext:graphics];
    if (snapshot != 0) {
        NSString *snapshotPath = elisa_appkit_canvas_string(snapshot);
        if (snapshotPath == nil) return 0;
        NSData *png = [bitmap representationUsingType:(NSBitmapImageFileType)image_type properties:@{}];
        if (png == nil || ![png writeToFile:snapshotPath atomically:YES]) return 0;
    }
    return 1;
}
void elisa_appkit_canvas_run(void) {
    [NSApp run];
}
void elisa_appkit_canvas_stop(void) {
    [NSApp stop:nil];
}
void elisa_appkit_canvas_redraw(void) { [elisa_canvas_view setNeedsDisplay:YES]; }
void elisa_appkit_canvas_close(void) {
    NSWindow *window = elisa_appkit_canvas_window();
    if (window != nil) [window performClose:nil];
}
void elisa_appkit_canvas_accessibility_reset(void) {
    [elisa_canvas_view removeAllToolTips];
}

// Elisa owns semantic identity and calls the typed setters immediately after
// adding a node. Return the retained native object as an opaque handle so the
// bridge does not maintain a second identifier lookup table for the in-flight
// frame. The live dictionary above still reuses objects across frames.
static ElisaAccessibilityElement *elisa_appkit_canvas_element(size_t handle) {
    if (handle == 0) return nil;
    id object = (__bridge id)(void *)handle;
    return [object isKindOfClass:[ElisaAccessibilityElement class]] ? object : nil;
}

size_t elisa_appkit_canvas_accessibility_add(size_t identifier, size_t previousHandle,
                                            size_t identifierString, size_t action, const void *role,
                                            const void *subrole, size_t cursor,
                                            size_t label, size_t help,
                                            float x, float y, float width, float height,
                                            int enabled, int focused) {
    if (label == 0 || elisa_canvas_view == nil) return 0;
    NSString *labelValue = elisa_appkit_canvas_string(label);
    if (labelValue == nil) return 0;
    NSString *helpValue = help == 0 ? nil : elisa_appkit_canvas_string(help);
    NSString *identifierValue = identifierString == 0 ? nil : elisa_appkit_canvas_string(identifierString);
    NSAccessibilityRole roleValue = role == NULL ? nil : (NSAccessibilityRole)elisa_appkit_canvas_string((size_t)role);
    NSAccessibilitySubrole subroleValue = subrole == NULL ? nil : (NSAccessibilitySubrole)elisa_appkit_canvas_string((size_t)subrole);
    if (role != NULL && roleValue == nil) return 0;
    if (subrole != NULL && subroleValue == nil) return 0;
    if (help != 0 && helpValue == nil) return 0;
    if (identifierString != 0 && identifierValue == nil) return 0;
    ElisaAccessibilityElement *element = elisa_appkit_canvas_element(previousHandle);
    BOOL isNew = element == nil;
    if (isNew) {
        element = [ElisaAccessibilityElement new];
        element.accessibilityParent = elisa_canvas_view;
        element.elisaIdentifier = identifier;
    }
    NSRect local = NSMakeRect(x, y, width, height);
    element.accessibilityRole = roleValue;
    element.accessibilitySubrole = subroleValue;
    element.accessibilityLabel = labelValue;
    element.accessibilityHelp = helpValue;
    element.accessibilityIdentifier = identifierValue;
    element.accessibilityEnabled = enabled != 0;
    element.accessibilityFocused = focused != 0;
    // Values are assigned by typed FFI setters chosen in Elisa. Resetting all
    // value slots here keeps reused semantic elements from retaining a stale
    // value when their framework role changes between frames.
    element.elisaSynchronizing = YES;
    element.accessibilityValue = nil;
    element.accessibilitySelectedText = nil;
    element.accessibilitySelectedTextRange = NSMakeRange(elisa_appkit_canvas_not_found(), 0);
    element.accessibilityMinValue = nil;
    element.accessibilityMaxValue = nil;
    element.elisaSynchronizing = NO;
    element.elisaIndex = action;
    element.elisaCursor = elisa_appkit_canvas_cursor(cursor);
    element.elisaLocalFrame = local;
    NSRect inWindow = [elisa_canvas_view convertRect:local toView:nil];
    NSWindow *window = elisa_appkit_canvas_window();
    if (window == nil) return 0;
    element.accessibilityFrame = [window convertRectToScreen:inWindow];
    // Retain a newly-created element until Elisa commits the ordered handle
    // list. Existing elements are already retained by the active child array;
    // identity/reuse itself is selected by Elisa from the previous-frame
    // handles rather than by a native semantic-ID dictionary.
    if (isNew) [elisa_accessibility_children addObject:element];
    return (size_t)(__bridge void *)element;
}

void elisa_appkit_canvas_accessibility_add_tooltip(size_t handle) {
    ElisaAccessibilityElement *element = elisa_appkit_canvas_element(handle);
    if (element == nil || elisa_canvas_view == nil) return;
    [elisa_canvas_view addToolTipRect:element.elisaLocalFrame owner:element userData:NULL];
}

void elisa_appkit_canvas_accessibility_set_boolean(size_t handle, int selected) {
    ElisaAccessibilityElement *element = elisa_appkit_canvas_element(handle);
    if (element == nil) return;
    element.elisaSynchronizing = YES;
    element.accessibilityValue = @(selected != 0);
    element.accessibilitySelectedText = nil;
    element.accessibilitySelectedTextRange = NSMakeRange(elisa_appkit_canvas_not_found(), 0);
    element.accessibilityMinValue = nil;
    element.accessibilityMaxValue = nil;
    element.elisaSynchronizing = NO;
}

void elisa_appkit_canvas_accessibility_set_range(size_t handle, float value,
                                                 float minimum, float maximum) {
    ElisaAccessibilityElement *element = elisa_appkit_canvas_element(handle);
    if (element == nil) return;
    element.elisaSynchronizing = YES;
    element.accessibilityValue = @(value);
    element.accessibilitySelectedText = nil;
    element.accessibilitySelectedTextRange = NSMakeRange(elisa_appkit_canvas_not_found(), 0);
    element.accessibilityMinValue = @(minimum);
    element.accessibilityMaxValue = @(maximum);
    element.elisaSynchronizing = NO;
}

void elisa_appkit_canvas_accessibility_set_text(size_t handle,
                                                 size_t textValue, size_t selectedTextValue,
                                                 size_t selectionLocation, size_t selectionLength) {
    ElisaAccessibilityElement *element = elisa_appkit_canvas_element(handle);
    if (element == nil) return;
    NSString *value = elisa_appkit_canvas_string(textValue);
    NSString *selected = elisa_appkit_canvas_string(selectedTextValue);
    if (value == nil || selected == nil) return;
    element.elisaSynchronizing = YES;
    element.accessibilityValue = value;
    element.accessibilitySelectedTextRange = NSMakeRange(selectionLocation, selectionLength);
    element.accessibilitySelectedText = selected;
    element.accessibilityMinValue = nil;
    element.accessibilityMaxValue = nil;
    element.elisaSynchronizing = NO;
}

void elisa_appkit_canvas_accessibility_notify(size_t handle, size_t notification) {
    ElisaAccessibilityElement *element = elisa_appkit_canvas_element(handle);
    if (element == nil || notification == 0) return;
    NSString *name = elisa_appkit_canvas_string(notification);
    if (name == nil) return;
    NSAccessibilityPostNotification(element, (NSAccessibilityNotificationName)name);
}

void elisa_appkit_canvas_accessibility_commit(const size_t *handles, size_t count) {
    if (count > elisa_appkit_canvas_accessibility_capacity()) return;
    if (count > 0 && handles == NULL) return;
    NSMutableArray *children = [NSMutableArray arrayWithCapacity:count];
    for (size_t index = 0; index < count; index++) {
        ElisaAccessibilityElement *element = elisa_appkit_canvas_element(handles[index]);
        if (element == nil) continue;
        [children addObject:element];
    }
    elisa_accessibility_children = children;
    [elisa_canvas_view setAccessibilityChildren:elisa_accessibility_children];
    [elisa_canvas_view setAccessibilityChildrenInNavigationOrder:elisa_accessibility_children];
    [[elisa_canvas_view window] invalidateCursorRectsForView:elisa_canvas_view];
}

void elisa_appkit_canvas_accessibility_post_layout_changed(size_t notification) {
    if (elisa_canvas_view == nil) return;
    if (notification == 0) return;
    NSString *name = elisa_appkit_canvas_string(notification);
    if (name == nil) return;
    NSAccessibilityPostNotification(elisa_canvas_view, (NSAccessibilityNotificationName)name);
}
