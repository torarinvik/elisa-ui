// AppKit host for elisa-ui's CUSTOM-PAINTED backend.
//
// AppKit owns the window, event queue and CoreGraphics context. Elisa owns the
// widget tree and emits UiCore::Command values; drawRect calls back into Elisa
// to replay that command batch into the current context.

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

extern void elisa_appkit_canvas_frame(size_t context);
extern void elisa_appkit_canvas_resize(float width, float height);
extern void elisa_appkit_canvas_pointer(int kind, float x, float y,
                                        float dx, float dy, int button);
extern void elisa_appkit_canvas_raw_key(int down, int keyCode, int character);
extern void elisa_appkit_canvas_raw_flags(int keyCode, size_t modifiers);
extern void elisa_appkit_canvas_focus_changed(int focused);
extern void elisa_appkit_canvas_accessibility_environment_changed(void);
extern void elisa_appkit_canvas_key_down_event(size_t event, int keyCode, int character, size_t modifiers);
extern void elisa_appkit_canvas_key_up(int keyCode, int character);
extern int elisa_appkit_canvas_accessibility_activate(size_t index);
extern int elisa_appkit_canvas_accessibility_adjust(size_t index, int direction);
extern void elisa_appkit_canvas_cancel_interaction(void);
extern int elisa_appkit_canvas_accepts_text(void);
extern int elisa_appkit_canvas_allows_text_readback(void);
extern size_t elisa_appkit_canvas_cursor_at(float x, float y);
extern void elisa_appkit_canvas_text_click(int kind, float x, int button, int clickCount);
extern void elisa_appkit_canvas_set_text(size_t index, const char *bytes, size_t length);
extern size_t elisa_appkit_canvas_selection_location(void);
extern size_t elisa_appkit_canvas_selection_length(void);
extern void elisa_appkit_canvas_set_selected_range(size_t index, size_t location, size_t length);
extern size_t elisa_appkit_canvas_marked_location(void);
extern size_t elisa_appkit_canvas_marked_length(void);
extern void elisa_appkit_canvas_commit_text(const char *bytes, size_t length,
                                            size_t replacementLocation, size_t replacementLength,
                                            int hasReplacement);
extern void elisa_appkit_canvas_update_marked_text(const char *bytes, size_t length,
                                                   size_t selectedLocation, size_t selectedLength,
                                                   size_t replacementLocation, size_t replacementLength,
                                                   int hasReplacement);
extern void elisa_appkit_canvas_unmark_text(void);
extern void elisa_appkit_canvas_text_selector(const char *selectorName);
extern int elisa_appkit_canvas_text_action(const char *selectorName);
extern int elisa_appkit_canvas_text_action_enabled(int action);
extern int elisa_appkit_canvas_perform_text_action(int action);
extern float elisa_appkit_canvas_character_x(size_t location);
extern float elisa_appkit_canvas_caret_y(void);
extern float elisa_appkit_canvas_caret_height(void);
extern size_t elisa_appkit_canvas_character_at_x(float x);
extern size_t elisa_appkit_canvas_range_location(size_t location);
extern size_t elisa_appkit_canvas_range_length(size_t location, size_t length);
extern const unsigned char *elisa_appkit_canvas_range_pointer(size_t location);
extern size_t elisa_appkit_canvas_range_byte_length(size_t location, size_t length);

@class ElisaCanvasView;
@class ElisaAccessibilityElement;
static NSWindow *elisa_canvas_window;
static ElisaCanvasView *elisa_canvas_view;
static NSMutableArray *elisa_accessibility_children;
static NSMutableArray *elisa_accessibility_next;
static NSMutableDictionary<NSNumber *, ElisaAccessibilityElement *> *elisa_accessibility_elements;
static NSUInteger elisa_canvas_frame_count;
static NSString *elisa_canvas_snapshot_path;
static NSString *elisa_canvas_application_name;
static NSMenu *elisa_canvas_menu_bar;
static NSMutableArray<NSMenu *> *elisa_canvas_menus;
static NSTimer *elisa_canvas_animation_timer;
static NSTrackingAreaOptions elisa_canvas_tracking_options;

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
    return elisa_appkit_canvas_accessibility_adjust(self.elisaIndex, 1) != 0;
}
- (BOOL)accessibilityPerformDecrement {
    return elisa_appkit_canvas_accessibility_adjust(self.elisaIndex, -1) != 0;
}
- (void)setAccessibilityValue:(id)value {
    [super setAccessibilityValue:value];
    if (self.elisaSynchronizing || ![value isKindOfClass:[NSString class]]) return;
    NSData *utf8 = [(NSString *)value dataUsingEncoding:NSUTF8StringEncoding];
    elisa_appkit_canvas_set_text(self.elisaIndex, utf8.bytes, utf8.length);
}
- (void)setAccessibilitySelectedTextRange:(NSRange)value {
    [super setAccessibilitySelectedTextRange:value];
    if (self.elisaSynchronizing || value.location == NSNotFound) return;
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

@interface ElisaCanvasDelegate : NSObject <NSWindowDelegate>
@end
@implementation ElisaCanvasDelegate
- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    [elisa_canvas_animation_timer invalidate];
    elisa_canvas_animation_timer = nil;
    elisa_appkit_canvas_cancel_interaction();
    [NSApp stop:nil];
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

static int elisa_event_character(NSEvent *event) {
    NSString *chars = [event charactersIgnoringModifiers];
    return chars.length == 1 ? [chars characterAtIndex:0] : 0;
}

void elisa_appkit_canvas_interpret_key_event(size_t event) {
    NSEvent *nativeEvent = (__bridge NSEvent *)(void *)event;
    if (nativeEvent != nil) [elisa_canvas_view interpretKeyEvents:@[nativeEvent]];
}

@implementation ElisaCanvasView
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isAccessibilityElement { return NO; }
- (NSArray *)accessibilityChildren { return elisa_accessibility_children ?: @[]; }
- (NSArray *)accessibilityChildrenInNavigationOrder { return elisa_accessibility_children ?: @[]; }
- (NSTrackingAreaOptions)trackingOptions {
    return elisa_canvas_tracking_options;
}
- (void)updateTrackingAreas {
    for (NSTrackingArea *area in [self trackingAreas]) [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:[self trackingOptions] owner:self userInfo:nil]];
    [super updateTrackingAreas];
}
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    elisa_canvas_frame_count += 1;
    CGContextRef context = [[NSGraphicsContext currentContext] CGContext];
    CGContextSaveGState(context);
    elisa_appkit_canvas_frame((size_t)context);
    CGContextRestoreGState(context);
}
- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    if (elisa_canvas_window != nil) elisa_appkit_canvas_resize(size.width, size.height);
}
- (NSPoint)eventPoint:(NSEvent *)event {
    return [self convertPoint:[event locationInWindow] fromView:nil];
}
- (void)updatePointerCursor:(NSPoint)point {
    NSCursor *nativeCursor = (__bridge NSCursor *)(void *)elisa_appkit_canvas_cursor_at(point.x, point.y);
    if (nativeCursor != nil) [nativeCursor set];
}
- (void)resetCursorRects {
    [super resetCursorRects];
    for (ElisaAccessibilityElement *element in elisa_accessibility_children) {
        if (element.elisaCursor != nil) [self addCursorRect:element.elisaLocalFrame cursor:element.elisaCursor];
    }
}
- (void)forwardMouseButton:(NSEvent *)event kind:(int)kind button:(int)button {
    NSPoint p = [self eventPoint:event];
    elisa_appkit_canvas_pointer(kind, p.x, p.y, 0, 0, button);
    // Forward native facts unchanged. Elisa decides whether this phase,
    // button and click count have meaning for the focused widget.
    elisa_appkit_canvas_text_click(kind, p.x, button, (int)event.clickCount);
}
- (void)mouseMoved:(NSEvent *)event { NSPoint p=[self eventPoint:event]; [self updatePointerCursor:p]; elisa_appkit_canvas_pointer(0,p.x,p.y,0,0,0); }
- (void)mouseDragged:(NSEvent *)event { [self mouseMoved:event]; }
- (void)rightMouseDragged:(NSEvent *)event { [self mouseMoved:event]; }
- (void)otherMouseDragged:(NSEvent *)event { [self mouseMoved:event]; }
- (void)mouseDown:(NSEvent *)event { [self forwardMouseButton:event kind:1 button:0]; }
- (void)rightMouseDown:(NSEvent *)event { [self forwardMouseButton:event kind:1 button:1]; }
- (void)otherMouseDown:(NSEvent *)event { [self forwardMouseButton:event kind:1 button:(int)event.buttonNumber]; }
- (void)mouseUp:(NSEvent *)event { [self forwardMouseButton:event kind:2 button:0]; }
- (void)rightMouseUp:(NSEvent *)event { [self forwardMouseButton:event kind:2 button:1]; }
- (void)otherMouseUp:(NSEvent *)event { [self forwardMouseButton:event kind:2 button:(int)event.buttonNumber]; }
- (void)mouseExited:(NSEvent *)event { (void)event; [(__bridge NSCursor *)(void *)elisa_appkit_canvas_arrow_cursor() set]; elisa_appkit_canvas_pointer(3,0,0,0,0,0); }
- (void)scrollWheel:(NSEvent *)event { NSPoint p=[self eventPoint:event]; elisa_appkit_canvas_pointer(4,p.x,p.y,[event scrollingDeltaX],[event scrollingDeltaY],0); }
- (void)keyDown:(NSEvent *)event {
    elisa_appkit_canvas_key_down_event((size_t)(__bridge void *)event, event.keyCode,
                                       elisa_event_character(event), (size_t)[event modifierFlags]);
}
- (void)keyUp:(NSEvent *)event {
    elisa_appkit_canvas_key_up(event.keyCode, elisa_event_character(event));
}
- (void)insertText:(id)input replacementRange:(NSRange)replacementRange {
    NSString *text = [input isKindOfClass:[NSAttributedString class]]
        ? [(NSAttributedString *)input string] : (NSString *)input;
    NSData *utf8 = [text dataUsingEncoding:NSUTF8StringEncoding];
    BOOL hasReplacement = replacementRange.location != NSNotFound;
    elisa_appkit_canvas_commit_text(utf8.bytes, utf8.length,
                                    hasReplacement ? replacementRange.location : 0,
                                    hasReplacement ? replacementRange.length : 0,
                                    hasReplacement);
}
- (void)doCommandBySelector:(SEL)selector {
    elisa_appkit_canvas_text_selector(sel_getName(selector));
}
- (void)selectAll:(id)sender {
    (void)sender;
    (void)elisa_appkit_canvas_perform_text_action(1);
}
- (void)undo:(id)sender {
    (void)sender;
    (void)elisa_appkit_canvas_perform_text_action(5);
}
- (void)redo:(id)sender {
    (void)sender;
    (void)elisa_appkit_canvas_perform_text_action(6);
}
- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
    int action = elisa_appkit_canvas_text_action(sel_getName(item.action));
    if (action != 0) return elisa_appkit_canvas_text_action_enabled(action) != 0;
    return YES;
}
- (void)copy:(id)sender {
    (void)sender;
    (void)elisa_appkit_canvas_perform_text_action(2);
}
- (void)cut:(id)sender {
    (void)sender;
    (void)elisa_appkit_canvas_perform_text_action(3);
}
- (void)paste:(id)sender {
    (void)sender;
    (void)elisa_appkit_canvas_perform_text_action(4);
}
- (BOOL)hasMarkedText { return elisa_appkit_canvas_marked_length() > 0; }
- (NSRange)markedRange {
    return self.hasMarkedText ? NSMakeRange(elisa_appkit_canvas_marked_location(),
                                            elisa_appkit_canvas_marked_length())
                              : NSMakeRange(NSNotFound, 0);
}
- (NSRange)selectedRange {
    return elisa_appkit_canvas_accepts_text()
        ? NSMakeRange(elisa_appkit_canvas_selection_location(), elisa_appkit_canvas_selection_length())
        : NSMakeRange(NSNotFound, 0);
}
- (void)setMarkedText:(id)text selectedRange:(NSRange)selectedRange replacementRange:(NSRange)replacementRange {
    NSString *plain = [text isKindOfClass:[NSAttributedString class]]
        ? [(NSAttributedString *)text string] : (NSString *)text;
    NSData *utf8 = [plain dataUsingEncoding:NSUTF8StringEncoding];
    BOOL hasReplacement = replacementRange.location != NSNotFound;
    elisa_appkit_canvas_update_marked_text(utf8.bytes, utf8.length,
                                           selectedRange.location, selectedRange.length,
                                           hasReplacement ? replacementRange.location : 0,
                                           hasReplacement ? replacementRange.length : 0,
                                           hasReplacement);
}
- (void)unmarkText { elisa_appkit_canvas_unmark_text(); }
- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText { return @[]; }
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
    if (range.location == NSNotFound || !elisa_appkit_canvas_allows_text_readback()) return nil;
    NSRange safe = NSMakeRange(elisa_appkit_canvas_range_location(range.location),
                               elisa_appkit_canvas_range_length(range.location, range.length));
    if (actualRange != NULL) *actualRange = safe;
    const unsigned char *bytes = elisa_appkit_canvas_range_pointer(range.location);
    size_t length = elisa_appkit_canvas_range_byte_length(range.location, range.length);
    NSString *text = length == 0 ? @"" :
        [[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];
    return text == nil ? nil : [[NSAttributedString alloc] initWithString:text];
}
- (NSUInteger)characterIndexForPoint:(NSPoint)point {
    if (!elisa_appkit_canvas_accepts_text() || self.window == nil) return NSNotFound;
    NSPoint inWindow = [self.window convertPointFromScreen:point];
    NSPoint local = [self convertPoint:inWindow fromView:nil];
    return elisa_appkit_canvas_character_at_x(local.x);
}
- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
    if (!elisa_appkit_canvas_accepts_text() || self.window == nil) {
        if (actualRange != NULL) *actualRange = NSMakeRange(NSNotFound, 0);
        return NSZeroRect;
    }
    size_t location = range.location == NSNotFound
        ? elisa_appkit_canvas_selection_location()
        : elisa_appkit_canvas_range_location(range.location);
    if (actualRange != NULL) *actualRange = NSMakeRange(location, 0);
    NSRect local = NSMakeRect(elisa_appkit_canvas_character_x(location), elisa_appkit_canvas_caret_y(),
                              1.0, elisa_appkit_canvas_caret_height());
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

int elisa_appkit_canvas_open(const char *title, size_t length, float width, float height,
                             int style, size_t tracking_options, int tabbing_mode, int restorable, int centered,
                             int activation_policy) {
    @autoreleasepool {
        elisa_canvas_frame_count = 0;
        elisa_canvas_tracking_options = (NSTrackingAreaOptions)tracking_options;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:(NSApplicationActivationPolicy)activation_policy];
        NSRect rect = NSMakeRect(0, 0, width, height);
        NSWindowStyleMask styleMask = (NSWindowStyleMask)style;
        NSWindow *window = [[NSWindow alloc] initWithContentRect:rect
            styleMask:styleMask
            backing:NSBackingStoreBuffered defer:NO];
        if (window == nil) return 0;
        NSString *name = [[NSString alloc] initWithBytes:title length:length encoding:NSUTF8StringEncoding];
        if (name != nil) [window setTitle:name];
        // Keep the global nil while NSView initialization calls setFrameSize:;
        // resize events must not reach the Elisa app before app_init.
        elisa_canvas_view = [[ElisaCanvasView alloc] initWithFrame:rect];
        elisa_accessibility_children = [NSMutableArray new];
        elisa_accessibility_next = [NSMutableArray new];
        elisa_accessibility_elements = [NSMutableDictionary new];
        elisa_canvas_window = window;
        elisa_canvas_delegate = [ElisaCanvasDelegate new];
        [window setDelegate:elisa_canvas_delegate];
        [window setContentView:elisa_canvas_view];
        [window setTabbingMode:(NSWindowTabbingMode)tabbing_mode];
        [window setRestorable:restorable != 0];
        if (centered) [window center];
        [window makeFirstResponder:elisa_canvas_view];
        return 1;
    }
}

void elisa_appkit_canvas_menus_begin(const char *title, size_t length) {
    NSString *name = [[NSString alloc] initWithBytes:title length:length encoding:NSUTF8StringEncoding];
    elisa_canvas_application_name = name ?: @"elisa-ui";
    elisa_canvas_menu_bar = [NSMenu new];
    elisa_canvas_menus = [NSMutableArray new];
}

int elisa_appkit_canvas_menu_add(const char *bytes, size_t length) {
    if (elisa_canvas_menu_bar == nil || elisa_canvas_menus == nil) return -1;
    NSString *title = [[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];
    if (title == nil) return -1;
    NSMenuItem *root = [[NSMenuItem alloc] initWithTitle:title action:NULL keyEquivalent:@""];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:title];
    [root setSubmenu:menu];
    [elisa_canvas_menu_bar addItem:root];
    [elisa_canvas_menus addObject:menu];
    return (int)elisa_canvas_menus.count - 1;
}

void elisa_appkit_canvas_menu_set_windows(int menuIndex) {
    if (menuIndex < 0 || (NSUInteger)menuIndex >= elisa_canvas_menus.count) return;
    [NSApp setWindowsMenu:elisa_canvas_menus[menuIndex]];
}

static void elisa_appkit_canvas_menu_add_item_title(int menuIndex, NSString *title,
                                                     const char *actionName, int key, size_t modifiers) {
    if (menuIndex < 0 || (NSUInteger)menuIndex >= elisa_canvas_menus.count) return;
    if (title == nil) return;
    SEL action = actionName == NULL || actionName[0] == '\0' ? NULL : sel_registerName(actionName);
    NSString *equivalent = @"";
    if (key > 0 && key <= UINT16_MAX) {
        unichar character = (unichar)key;
        equivalent = [NSString stringWithCharacters:&character length:1];
    }
    NSMenuItem *item = [elisa_canvas_menus[menuIndex]
        addItemWithTitle:title action:action keyEquivalent:equivalent];
    item.keyEquivalentModifierMask = (NSEventModifierFlags)modifiers;
}

void elisa_appkit_canvas_menu_add_item(int menuIndex, const char *bytes, size_t length,
                                        const char *actionName, int key, size_t modifiers) {
    NSString *title = [[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];
    elisa_appkit_canvas_menu_add_item_title(menuIndex, title, actionName, key, modifiers);
}

void elisa_appkit_canvas_menu_add_application_item(int menuIndex, const char *bytes, size_t length,
                                                    const char *actionName, int key, size_t modifiers) {
    NSString *title = [[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];
    if (title != nil) title = [title stringByAppendingString:elisa_canvas_application_name];
    elisa_appkit_canvas_menu_add_item_title(menuIndex, title, actionName, key, modifiers);
}

size_t elisa_appkit_canvas_modifier_command(void) { return NSEventModifierFlagCommand; }
size_t elisa_appkit_canvas_modifier_shift(void) { return NSEventModifierFlagShift; }
size_t elisa_appkit_canvas_modifier_option(void) { return NSEventModifierFlagOption; }
size_t elisa_appkit_canvas_modifier_control(void) { return NSEventModifierFlagControl; }
size_t elisa_appkit_canvas_modifier_device_independent_mask(void) {
    return NSEventModifierFlagDeviceIndependentFlagsMask;
}

void elisa_appkit_canvas_menu_add_separator(int menuIndex) {
    if (menuIndex < 0 || (NSUInteger)menuIndex >= elisa_canvas_menus.count) return;
    [elisa_canvas_menus[menuIndex] addItem:[NSMenuItem separatorItem]];
}

void elisa_appkit_canvas_menus_commit(void) {
    if (elisa_canvas_menu_bar != nil) [NSApp setMainMenu:elisa_canvas_menu_bar];
}

void elisa_appkit_canvas_set_snapshot_path(const char *path) {
    elisa_canvas_snapshot_path = path == NULL ? nil : [NSString stringWithUTF8String:path];
}

int elisa_appkit_canvas_clipboard_write(const unsigned char *bytes, size_t length) {
    if (bytes == NULL) return 0;
    NSString *text = [[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];
    if (text == nil) return 0;
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    return [pasteboard setString:text forType:NSPasteboardTypeString];
}

size_t elisa_appkit_canvas_clipboard_read(unsigned char *buffer, size_t capacity) {
    if (buffer == NULL || capacity == 0) return 0;
    NSString *text = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
    if (text == nil) return 0;
    NSData *utf8 = [text dataUsingEncoding:NSUTF8StringEncoding];
    size_t take = MIN((size_t)utf8.length, capacity);
    if (take > 0) memcpy(buffer, utf8.bytes, take);
    return take;
}

void elisa_appkit_canvas_schedule_redraw(float delay) {
    [elisa_canvas_animation_timer invalidate];
    elisa_canvas_animation_timer = nil;
    elisa_canvas_animation_timer = [NSTimer timerWithTimeInterval:delay repeats:NO block:^(NSTimer *timer) {
        (void)timer;
        [elisa_canvas_view setNeedsDisplay:YES];
    }];
    [NSRunLoop.mainRunLoop addTimer:elisa_canvas_animation_timer forMode:NSRunLoopCommonModes];
}

void elisa_appkit_canvas_cancel_redraw(void) {
    [elisa_canvas_animation_timer invalidate];
    elisa_canvas_animation_timer = nil;
}

void elisa_appkit_canvas_set_min_size(float width, float height) {
    [elisa_canvas_window setContentMinSize:NSMakeSize(width, height)];
}

int elisa_appkit_canvas_present(int activate) {
    [elisa_canvas_window makeKeyAndOrderFront:nil];
    if (activate) [NSApp activateIgnoringOtherApps:YES];
    [elisa_canvas_view setNeedsDisplay:YES];
    return 1;
}
int elisa_appkit_canvas_present_headless(void) {
    // Exercise the real frame, painter and semantic bridge without ordering
    // a window onscreen or stealing focus from the user's current app.
    NSUInteger before = elisa_canvas_frame_count;
    NSRect bounds = elisa_canvas_view.bounds;
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
        pixelsWide:MAX(1, (NSInteger)ceil(bounds.size.width))
        pixelsHigh:MAX(1, (NSInteger)ceil(bounds.size.height))
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSCalibratedRGBColorSpace
        bitmapFormat:0 bytesPerRow:0 bitsPerPixel:0];
    NSGraphicsContext *graphics = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [elisa_canvas_view displayRectIgnoringOpacity:bounds inContext:graphics];
    if (elisa_canvas_frame_count <= before) return 0;
    if (elisa_canvas_snapshot_path.length > 0) {
        NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if (png == nil || ![png writeToFile:elisa_canvas_snapshot_path atomically:YES]) return 0;
    }
    return 1;
}
void elisa_appkit_canvas_run(void) {
    [NSApp run];
}
void elisa_appkit_canvas_redraw(void) { [elisa_canvas_view setNeedsDisplay:YES]; }
void elisa_appkit_canvas_close(void) {
    [elisa_canvas_animation_timer invalidate];
    elisa_canvas_animation_timer = nil;
    [elisa_canvas_window performClose:nil];
}
void elisa_appkit_canvas_accessibility_reset(void) {
    [elisa_accessibility_next removeAllObjects];
    [elisa_canvas_view removeAllToolTips];
}

static ElisaAccessibilityElement *elisa_appkit_canvas_pending_element(size_t identifier) {
    for (ElisaAccessibilityElement *element in elisa_accessibility_next) {
        if (element.elisaIdentifier == identifier) return element;
    }
    return nil;
}

void elisa_appkit_canvas_accessibility_add(size_t identifier, size_t action, const void *role,
                                            const void *subrole, size_t cursor,
                                            const char *bytes, size_t length,
                                            const char *helpBytes, size_t helpLength,
                                            float x, float y, float width, float height,
                                            int enabled, int focused) {
    if (bytes == NULL || length == 0 || elisa_canvas_view == nil) return;
    NSString *label = [[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];
    if (label == nil) return;
    NSNumber *key = @(identifier);
    ElisaAccessibilityElement *element = elisa_accessibility_elements[key];
    BOOL isNew = element == nil;
    if (isNew) {
        element = [ElisaAccessibilityElement new];
        element.accessibilityParent = elisa_canvas_view;
        element.elisaIdentifier = identifier;
    }
    NSRect local = NSMakeRect(x, y, width, height);
    element.accessibilityRole = (__bridge NSAccessibilityRole)role;
    element.accessibilitySubrole = subrole == NULL ? nil : (__bridge NSAccessibilitySubrole)subrole;
    element.accessibilityLabel = label;
    if (helpBytes != NULL && helpLength > 0) {
        element.accessibilityHelp = [[NSString alloc] initWithBytes:helpBytes length:helpLength encoding:NSUTF8StringEncoding];
    } else {
        element.accessibilityHelp = nil;
    }
    element.accessibilityIdentifier = [NSString stringWithFormat:@"elisa-ui-%zu", identifier];
    element.accessibilityEnabled = enabled != 0;
    element.accessibilityFocused = focused != 0;
    // Values are assigned by typed FFI setters chosen in Elisa. Resetting all
    // value slots here keeps reused semantic elements from retaining a stale
    // value when their framework role changes between frames.
    element.elisaSynchronizing = YES;
    element.accessibilityValue = nil;
    element.accessibilitySelectedText = nil;
    element.accessibilitySelectedTextRange = NSMakeRange(NSNotFound, 0);
    element.accessibilityMinValue = nil;
    element.accessibilityMaxValue = nil;
    element.elisaSynchronizing = NO;
    element.elisaIndex = action;
    element.elisaCursor = (__bridge NSCursor *)(void *)cursor;
    element.elisaLocalFrame = local;
    NSRect inWindow = [elisa_canvas_view convertRect:local toView:nil];
    element.accessibilityFrame = [elisa_canvas_window convertRectToScreen:inWindow];
    [elisa_accessibility_next addObject:element];
}

void elisa_appkit_canvas_accessibility_add_tooltip(size_t identifier) {
    ElisaAccessibilityElement *element = elisa_appkit_canvas_pending_element(identifier);
    if (element == nil || elisa_canvas_view == nil) return;
    [elisa_canvas_view addToolTipRect:element.elisaLocalFrame owner:element userData:NULL];
}

void elisa_appkit_canvas_accessibility_set_boolean(size_t identifier, int selected) {
    ElisaAccessibilityElement *element = elisa_appkit_canvas_pending_element(identifier);
    if (element == nil) return;
    element.elisaSynchronizing = YES;
    element.accessibilityValue = @(selected != 0);
    element.accessibilitySelectedText = nil;
    element.accessibilitySelectedTextRange = NSMakeRange(NSNotFound, 0);
    element.accessibilityMinValue = nil;
    element.accessibilityMaxValue = nil;
    element.elisaSynchronizing = NO;
}

void elisa_appkit_canvas_accessibility_set_range(size_t identifier, float value) {
    ElisaAccessibilityElement *element = elisa_appkit_canvas_pending_element(identifier);
    if (element == nil) return;
    element.elisaSynchronizing = YES;
    element.accessibilityValue = @(value);
    element.accessibilitySelectedText = nil;
    element.accessibilitySelectedTextRange = NSMakeRange(NSNotFound, 0);
    element.accessibilityMinValue = @0.0;
    element.accessibilityMaxValue = @1.0;
    element.elisaSynchronizing = NO;
}

void elisa_appkit_canvas_accessibility_set_text(size_t identifier,
                                                 const char *textBytes, size_t textLength,
                                                 const char *selectedTextBytes, size_t selectedTextLength,
                                                 size_t selectionLocation, size_t selectionLength) {
    ElisaAccessibilityElement *element = elisa_appkit_canvas_pending_element(identifier);
    if (element == nil) return;
    NSString *textValue = textBytes != NULL
        ? [[NSString alloc] initWithBytes:textBytes length:textLength encoding:NSUTF8StringEncoding]
        : @"";
    NSString *selectedTextValue = selectedTextBytes != NULL
        ? [[NSString alloc] initWithBytes:selectedTextBytes length:selectedTextLength encoding:NSUTF8StringEncoding]
        : @"";
    element.elisaSynchronizing = YES;
    element.accessibilityValue = textValue ?: @"";
    element.accessibilitySelectedTextRange = NSMakeRange(selectionLocation, selectionLength);
    element.accessibilitySelectedText = selectedTextValue ?: @"";
    element.accessibilityMinValue = nil;
    element.accessibilityMaxValue = nil;
    element.elisaSynchronizing = NO;
}

void elisa_appkit_canvas_accessibility_notify(size_t identifier, size_t notification) {
    ElisaAccessibilityElement *element = elisa_appkit_canvas_pending_element(identifier);
    if (element == nil || notification == 0) return;
    NSAccessibilityPostNotification(element, (__bridge NSAccessibilityNotificationName)(void *)notification);
}

void elisa_appkit_canvas_accessibility_commit(void) {
    elisa_accessibility_children = [elisa_accessibility_next mutableCopy];
    NSMutableDictionary<NSNumber *, ElisaAccessibilityElement *> *live = [NSMutableDictionary new];
    for (ElisaAccessibilityElement *element in elisa_accessibility_children) {
        live[@(element.elisaIdentifier)] = element;
    }
    elisa_accessibility_elements = live;
    [elisa_canvas_view setAccessibilityChildren:elisa_accessibility_children];
    [elisa_canvas_view setAccessibilityChildrenInNavigationOrder:elisa_accessibility_children];
    [[elisa_canvas_view window] invalidateCursorRectsForView:elisa_canvas_view];
}

void elisa_appkit_canvas_accessibility_post_layout_changed(void) {
    if (elisa_canvas_view == nil) return;
    NSAccessibilityPostNotification(elisa_canvas_view, NSAccessibilityLayoutChangedNotification);
}
