// AppKit host for elisa-ui's CUSTOM-PAINTED backend.
//
// AppKit owns the window, event queue and CoreGraphics context. Elisa owns the
// widget tree and emits UiCore::Command values; drawRect calls back into Elisa
// to replay that command batch into the current context.

#import <Cocoa/Cocoa.h>

extern void elisa_appkit_canvas_frame(size_t context);
extern void elisa_appkit_canvas_resize(float width, float height);
extern void elisa_appkit_canvas_pointer(int kind, float x, float y,
                                        float dx, float dy, int button);
extern void elisa_appkit_canvas_key(int down, int code);
extern void elisa_appkit_canvas_raw_key(int down, int keyCode, int character);
extern void elisa_appkit_canvas_raw_flags(int keyCode, int shift, int control, int alt, int superKey);
extern void elisa_appkit_canvas_focus_changed(int focused);
extern void elisa_appkit_canvas_accessibility_environment_changed(void);
extern int elisa_appkit_canvas_key_down_route(int character, int shift, int control,
                                               int alt, int superKey);
extern void elisa_appkit_canvas_key_up(int keyCode, int character);
extern int elisa_appkit_canvas_accessibility_activate(size_t index);
extern int elisa_appkit_canvas_accessibility_adjust(size_t index, int direction);
extern void elisa_appkit_canvas_cancel_interaction(void);
extern int elisa_appkit_canvas_accepts_text(void);
extern int elisa_appkit_canvas_allows_text_readback(void);
extern int elisa_appkit_canvas_cursor_at(float x, float y);
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
extern void elisa_appkit_canvas_text_selector(int selectorToken);
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

@interface ElisaAccessibilityElement : NSAccessibilityElement
@property(nonatomic) size_t elisaIndex;
@property(nonatomic) size_t elisaIdentifier;
@property(nonatomic) int elisaCursor;
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

static SEL elisa_menu_action(int action) {
    switch (action) {
        case 1: return @selector(orderFrontStandardAboutPanel:);
        case 2: return @selector(hide:);
        case 3: return @selector(hideOtherApplications:);
        case 4: return @selector(unhideAllApplications:);
        case 5: return @selector(terminate:);
        case 6: return @selector(undo:);
        case 7: return @selector(redo:);
        case 8: return @selector(cut:);
        case 9: return @selector(copy:);
        case 10: return @selector(paste:);
        case 11: return @selector(selectAll:);
        case 12: return @selector(performMiniaturize:);
        case 13: return @selector(performZoom:);
        case 14: return @selector(arrangeInFront:);
        default: return NULL;
    }
}

static int elisa_event_character(NSEvent *event) {
    NSString *chars = [event charactersIgnoringModifiers];
    return chars.length == 1 ? [chars characterAtIndex:0] : 0;
}

static int elisa_text_action(SEL selector) {
    if (selector == @selector(selectAll:)) return 1;
    if (selector == @selector(copy:)) return 2;
    if (selector == @selector(cut:)) return 3;
    if (selector == @selector(paste:)) return 4;
    if (selector == @selector(undo:)) return 5;
    if (selector == @selector(redo:)) return 6;
    return 0;
}

@implementation ElisaCanvasView
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isAccessibilityElement { return NO; }
- (NSArray *)accessibilityChildren { return elisa_accessibility_children ?: @[]; }
- (NSArray *)accessibilityChildrenInNavigationOrder { return elisa_accessibility_children ?: @[]; }
- (NSTrackingAreaOptions)trackingOptions {
    return NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited |
           NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect;
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
    int cursor = elisa_appkit_canvas_cursor_at(point.x, point.y);
    NSCursor *nativeCursor = cursor == 1 ? NSCursor.pointingHandCursor :
                             cursor == 2 ? NSCursor.IBeamCursor : NSCursor.arrowCursor;
    [nativeCursor set];
}
- (void)resetCursorRects {
    [super resetCursorRects];
    for (ElisaAccessibilityElement *element in elisa_accessibility_children) {
        if (element.elisaCursor == 1) {
            [self addCursorRect:element.elisaLocalFrame cursor:[NSCursor pointingHandCursor]];
        } else if (element.elisaCursor == 2) {
            [self addCursorRect:element.elisaLocalFrame cursor:[NSCursor IBeamCursor]];
        }
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
- (void)mouseExited:(NSEvent *)event { (void)event; [[NSCursor arrowCursor] set]; elisa_appkit_canvas_pointer(3,0,0,0,0,0); }
- (void)scrollWheel:(NSEvent *)event { NSPoint p=[self eventPoint:event]; elisa_appkit_canvas_pointer(4,p.x,p.y,[event scrollingDeltaX],[event scrollingDeltaY],0); }
- (void)keyDown:(NSEvent *)event {
    NSEventModifierFlags flags = [event modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask;
    int route = elisa_appkit_canvas_key_down_route(elisa_event_character(event),
        (flags & NSEventModifierFlagShift) != 0,
        (flags & NSEventModifierFlagControl) != 0,
        (flags & NSEventModifierFlagOption) != 0,
        (flags & NSEventModifierFlagCommand) != 0);
    if (route >= 2) {
        (void)elisa_appkit_canvas_perform_text_action(route - 1);
        return;
    }
    if (route == 1) {
        [self interpretKeyEvents:@[event]];
        return;
    }
    elisa_appkit_canvas_raw_key(1, event.keyCode, elisa_event_character(event));
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
    int token = 0;
    if (selector == @selector(moveLeft:)) token = 1;
    else if (selector == @selector(moveRight:)) token = 2;
    else if (selector == @selector(moveLeftAndModifySelection:)) token = 3;
    else if (selector == @selector(moveRightAndModifySelection:)) token = 4;
    else if (selector == @selector(moveToBeginningOfLine:)) token = 5;
    else if (selector == @selector(moveToEndOfLine:)) token = 6;
    else if (selector == @selector(moveToBeginningOfLineAndModifySelection:)) token = 7;
    else if (selector == @selector(moveToEndOfLineAndModifySelection:)) token = 8;
    else if (selector == @selector(deleteBackward:)) token = 9;
    else if (selector == @selector(deleteForward:)) token = 10;
    else if (selector == @selector(insertNewline:)) token = 11;
    else if (selector == @selector(insertTab:)) token = 12;
    else if (selector == @selector(insertBacktab:)) token = 13;
    else if (selector == @selector(moveWordLeft:)) token = 14;
    else if (selector == @selector(moveWordRight:)) token = 15;
    else if (selector == @selector(moveWordLeftAndModifySelection:)) token = 16;
    else if (selector == @selector(moveWordRightAndModifySelection:)) token = 17;
    else if (selector == @selector(deleteWordBackward:)) token = 18;
    else if (selector == @selector(deleteWordForward:)) token = 19;
    if (token != 0) {
        elisa_appkit_canvas_text_selector(token);
    }
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
    int action = elisa_text_action(item.action);
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
    NSEventModifierFlags flags = [event modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask;
    elisa_appkit_canvas_raw_flags(event.keyCode,
        (flags & NSEventModifierFlagShift) != 0,
        (flags & NSEventModifierFlagControl) != 0,
        (flags & NSEventModifierFlagOption) != 0,
        (flags & NSEventModifierFlagCommand) != 0);
}
@end

int elisa_appkit_canvas_open(const char *title, size_t length, float width, float height,
                             int style, int tabbing, int restorable, int centered, int headless) {
    @autoreleasepool {
        elisa_canvas_frame_count = 0;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:headless
            ? NSApplicationActivationPolicyProhibited
            : NSApplicationActivationPolicyRegular];
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
        [window setTabbingMode:tabbing ? NSWindowTabbingModePreferred : NSWindowTabbingModeDisallowed];
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

int elisa_appkit_canvas_menu_add(const char *bytes, size_t length, int windowsMenu) {
    if (elisa_canvas_menu_bar == nil || elisa_canvas_menus == nil) return -1;
    NSString *title = [[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];
    if (title == nil) return -1;
    NSMenuItem *root = [[NSMenuItem alloc] initWithTitle:title action:NULL keyEquivalent:@""];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:title];
    [root setSubmenu:menu];
    [elisa_canvas_menu_bar addItem:root];
    [elisa_canvas_menus addObject:menu];
    if (windowsMenu) [NSApp setWindowsMenu:menu];
    return (int)elisa_canvas_menus.count - 1;
}

void elisa_appkit_canvas_menu_add_item(int menuIndex, const char *bytes, size_t length,
                                        int appendApplicationName, int action, int key,
                                        int modifiers) {
    if (menuIndex < 0 || (NSUInteger)menuIndex >= elisa_canvas_menus.count) return;
    NSString *title = [[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];
    if (title == nil) return;
    if (appendApplicationName) title = [title stringByAppendingString:elisa_canvas_application_name];
    NSString *equivalent = @"";
    if (key > 0 && key <= UINT16_MAX) {
        unichar character = (unichar)key;
        equivalent = [NSString stringWithCharacters:&character length:1];
    }
    NSMenuItem *item = [elisa_canvas_menus[menuIndex]
        addItemWithTitle:title action:elisa_menu_action(action) keyEquivalent:equivalent];
    NSEventModifierFlags mask = 0;
    if (modifiers & 1) mask |= NSEventModifierFlagCommand;
    if (modifiers & 2) mask |= NSEventModifierFlagShift;
    if (modifiers & 4) mask |= NSEventModifierFlagOption;
    if (modifiers & 8) mask |= NSEventModifierFlagControl;
    item.keyEquivalentModifierMask = mask;
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

int elisa_appkit_canvas_clipboard_has_text(void) {
    return [[NSPasteboard generalPasteboard]
        availableTypeFromArray:@[NSPasteboardTypeString]] != nil;
}

int elisa_appkit_canvas_clipboard_write(const unsigned char *bytes, size_t length) {
    if (bytes == NULL || length == 0) return 0;
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
    if (delay <= 0.0f) return;
    elisa_canvas_animation_timer = [NSTimer timerWithTimeInterval:delay repeats:NO block:^(NSTimer *timer) {
        (void)timer;
        [elisa_canvas_view setNeedsDisplay:YES];
    }];
    [NSRunLoop.mainRunLoop addTimer:elisa_canvas_animation_timer forMode:NSRunLoopCommonModes];
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

void elisa_appkit_canvas_accessibility_add(size_t identifier, size_t action, int role,
                                            int tooltip, int valueKind, int cursor, int notifications,
                                            const char *bytes, size_t length,
                                            const char *helpBytes, size_t helpLength,
                                            const char *textBytes, size_t textLength,
                                            const char *selectedTextBytes, size_t selectedTextLength,
                                            float x, float y, float width, float height,
                                            int enabled, int focused, int selected, float value,
                                            size_t selectionLocation, size_t selectionLength) {
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
    NSString *nextRole = role == 1 ? NSAccessibilityButtonRole :
                         role == 2 ? NSAccessibilityRadioButtonRole :
                         role == 3 ? NSAccessibilityCheckBoxRole :
                         role == 4 ? NSAccessibilitySliderRole :
                         role == 5 ? NSAccessibilityProgressIndicatorRole :
                         (role == 6 || role == 7) ? NSAccessibilityTextFieldRole : NSAccessibilityStaticTextRole;
    NSString *nextSubrole = role == 7 ? NSAccessibilitySecureTextFieldSubrole : nil;
    element.accessibilityRole = nextRole;
    element.accessibilitySubrole = nextSubrole;
    element.accessibilityLabel = label;
    if (helpBytes != NULL && helpLength > 0) {
        element.accessibilityHelp = [[NSString alloc] initWithBytes:helpBytes length:helpLength encoding:NSUTF8StringEncoding];
    } else {
        element.accessibilityHelp = nil;
    }
    element.accessibilityIdentifier = [NSString stringWithFormat:@"elisa-ui-%zu", identifier];
    element.accessibilityEnabled = enabled != 0;
    element.accessibilityFocused = focused != 0;
    element.elisaSynchronizing = YES;
    if (valueKind == 1) {
        element.accessibilityValue = @(selected != 0);
        element.accessibilitySelectedText = nil;
        element.accessibilitySelectedTextRange = NSMakeRange(NSNotFound, 0);
        element.accessibilityMinValue = nil;
        element.accessibilityMaxValue = nil;
    } else if (valueKind == 2) {
        element.accessibilityValue = @(value);
        element.accessibilitySelectedText = nil;
        element.accessibilitySelectedTextRange = NSMakeRange(NSNotFound, 0);
        element.accessibilityMinValue = @0.0;
        element.accessibilityMaxValue = @1.0;
    } else if (valueKind == 3) {
        NSString *textValue = textBytes != NULL
            ? [[NSString alloc] initWithBytes:textBytes length:textLength encoding:NSUTF8StringEncoding]
            : @"";
        element.accessibilityValue = textValue ?: @"";
        NSString *selectedTextValue = selectedTextBytes != NULL
            ? [[NSString alloc] initWithBytes:selectedTextBytes length:selectedTextLength encoding:NSUTF8StringEncoding]
            : @"";
        element.accessibilitySelectedTextRange = NSMakeRange(selectionLocation, selectionLength);
        element.accessibilitySelectedText = selectedTextValue ?: @"";
        element.accessibilityMinValue = nil;
        element.accessibilityMaxValue = nil;
    } else {
        element.accessibilityValue = nil;
        element.accessibilitySelectedText = nil;
        element.accessibilitySelectedTextRange = NSMakeRange(NSNotFound, 0);
        element.accessibilityMinValue = nil;
        element.accessibilityMaxValue = nil;
    }
    element.elisaSynchronizing = NO;
    element.elisaIndex = action;
    element.elisaCursor = cursor;
    element.elisaLocalFrame = local;
    NSRect inWindow = [elisa_canvas_view convertRect:local toView:nil];
    element.accessibilityFrame = [elisa_canvas_window convertRectToScreen:inWindow];
    [elisa_accessibility_next addObject:element];
    if (tooltip) {
        [elisa_canvas_view addToolTipRect:local owner:element userData:NULL];
    }
    if (notifications & 1) NSAccessibilityPostNotification(element, NSAccessibilityValueChangedNotification);
    if (notifications & 2) NSAccessibilityPostNotification(element, NSAccessibilityFocusedUIElementChangedNotification);
    if (notifications & 4) NSAccessibilityPostNotification(element, NSAccessibilitySelectedTextChangedNotification);
}

void elisa_appkit_canvas_accessibility_commit(int layoutChanged) {
    elisa_accessibility_children = [elisa_accessibility_next mutableCopy];
    NSMutableDictionary<NSNumber *, ElisaAccessibilityElement *> *live = [NSMutableDictionary new];
    for (ElisaAccessibilityElement *element in elisa_accessibility_children) {
        live[@(element.elisaIdentifier)] = element;
    }
    elisa_accessibility_elements = live;
    [elisa_canvas_view setAccessibilityChildren:elisa_accessibility_children];
    [elisa_canvas_view setAccessibilityChildrenInNavigationOrder:elisa_accessibility_children];
    [[elisa_canvas_view window] invalidateCursorRectsForView:elisa_canvas_view];
    if (layoutChanged) {
        NSAccessibilityPostNotification(elisa_canvas_view, NSAccessibilityLayoutChangedNotification);
    }
}
