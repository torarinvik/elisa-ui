// AppKit host for elisa-ui's CUSTOM-PAINTED backend.
//
// AppKit owns the window, event queue and CoreGraphics context. Elisa owns the
// widget tree and emits UiCore::Command values; drawRect calls back into Elisa
// to replay that command batch into the current context.

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

extern void elisa_appkit_canvas_frame(size_t windowHandle, size_t context);
extern void elisa_appkit_canvas_resize(size_t windowHandle, float width, float height);
extern size_t elisa_appkit_canvas_pointer_move_event(size_t windowHandle, float x, float y);
extern void elisa_appkit_canvas_pointer_button(size_t windowHandle, float x, float y, int button, int down, int clickCount);
extern void elisa_appkit_canvas_pointer_scroll(size_t windowHandle, float x, float y, float dx, float dy);
extern void elisa_appkit_canvas_raw_flags(size_t windowHandle, int keyCode, size_t modifiers);
extern void elisa_appkit_canvas_focus_changed(size_t windowHandle, int focused);
extern void elisa_appkit_canvas_accessibility_environment_changed(size_t windowHandle);
extern void elisa_appkit_canvas_window_closed(size_t windowHandle);
extern void elisa_appkit_canvas_rebuild_cursor_rects(size_t windowHandle);
extern int elisa_appkit_canvas_render_headless(size_t windowHandle,
                                               size_t snapshot,
                                               int pixelsWidth,
                                               int pixelsHeight);
extern void elisa_appkit_canvas_key_down_event(size_t windowHandle, size_t event, int keyCode, size_t character, size_t modifiers);
extern void elisa_appkit_canvas_key_up(size_t windowHandle, int keyCode, size_t character);
extern int elisa_appkit_canvas_accessibility_activate(size_t windowHandle, size_t handle);
extern int elisa_appkit_canvas_accessibility_adjust(size_t windowHandle, size_t handle, int direction);
extern size_t elisa_appkit_canvas_accessibility_tooltip_text(size_t windowHandle, size_t handle);
extern size_t elisa_appkit_canvas_accessibility_set_value(size_t windowHandle, size_t handle, size_t value);
extern int elisa_appkit_canvas_accessibility_increment_direction(void);
extern int elisa_appkit_canvas_accessibility_decrement_direction(void);
extern const size_t elisa_appkit_canvas_not_found;
extern int elisa_appkit_canvas_has_marked_text(size_t windowHandle);
extern size_t elisa_appkit_canvas_pointer_leave_event(size_t windowHandle);
extern void elisa_appkit_canvas_timer_fired(size_t windowHandle);
extern size_t elisa_appkit_canvas_selection_location(size_t windowHandle);
extern size_t elisa_appkit_canvas_selection_length(size_t windowHandle);
extern int elisa_appkit_canvas_set_selected_range(size_t windowHandle, size_t handle, size_t location, size_t length);
extern size_t elisa_appkit_canvas_marked_location(size_t windowHandle);
extern size_t elisa_appkit_canvas_marked_length(size_t windowHandle);
extern void elisa_appkit_canvas_commit_text(size_t windowHandle, size_t text,
                                            size_t replacementLocation, size_t replacementLength);
extern void elisa_appkit_canvas_update_marked_text(size_t windowHandle, size_t text,
                                                   size_t selectedLocation, size_t selectedLength,
                                                   size_t replacementLocation, size_t replacementLength);
extern void elisa_appkit_canvas_unmark_text(size_t windowHandle);
extern size_t elisa_appkit_canvas_valid_marked_attributes(size_t windowHandle);
extern void elisa_appkit_canvas_text_selector_handle(size_t windowHandle, size_t selector);
extern void elisa_appkit_canvas_text_action_selector(size_t windowHandle, size_t selector);
extern int elisa_appkit_canvas_text_action_valid_selector(size_t windowHandle, size_t selector);
extern size_t elisa_appkit_canvas_character_at_x(size_t windowHandle, float x);
extern size_t elisa_appkit_canvas_attributed_substring(size_t windowHandle, size_t location, size_t length,
                                                       size_t *actualLocation, size_t *actualLength);
extern int elisa_appkit_canvas_first_rect(size_t windowHandle, size_t location, size_t length,
                                          size_t *actualLocation, size_t *actualLength,
                                          float *x, float *y, float *width, float *height);
extern int elisa_appkit_canvas_view_is_flipped(void);
extern int elisa_appkit_canvas_view_accepts_first_responder(void);
extern int elisa_appkit_canvas_view_is_accessibility_element(void);
extern size_t elisa_appkit_canvas_tracking_options(void);

@class ElisaCanvasView;
@class ElisaAccessibilityElement;
static NSString *elisa_appkit_canvas_string(size_t handle);
static NSNumber *elisa_appkit_canvas_number(size_t handle);
static NSAttributedString *elisa_appkit_canvas_attributed_string(size_t handle);

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
- (void)elisaSetAccessibilityValue:(id)value;
- (void)elisaSetAccessibilitySelectedTextRange:(NSRange)value;
@end

static size_t elisa_appkit_canvas_element_window_handle(ElisaAccessibilityElement *element);

@implementation ElisaAccessibilityElement
// Accessibility callbacks pass the opaque element handle directly to Elisa;
// semantic-slot lookup and widget authorization stay outside the Cocoa shim.
- (BOOL)accessibilityPerformPress {
    return elisa_appkit_canvas_accessibility_activate(
        elisa_appkit_canvas_element_window_handle(self), (size_t)(__bridge void *)self) != 0;
}
- (BOOL)accessibilityPerformIncrement {
    return elisa_appkit_canvas_accessibility_adjust(elisa_appkit_canvas_element_window_handle(self),
        (size_t)(__bridge void *)self,
        elisa_appkit_canvas_accessibility_increment_direction()) != 0;
}
- (BOOL)accessibilityPerformDecrement {
    return elisa_appkit_canvas_accessibility_adjust(elisa_appkit_canvas_element_window_handle(self),
        (size_t)(__bridge void *)self,
        elisa_appkit_canvas_accessibility_decrement_direction()) != 0;
}
- (void)setAccessibilityValue:(id)value {
    // Elisa classifies the borrowed value, applies the widget policy and
    // returns a retained string or normalized number only when it accepted the
    // edit. The native adapter validates that returned object, mirrors it into
    // the superclass, then releases the one retained result.
    size_t native = elisa_appkit_canvas_accessibility_set_value(
        elisa_appkit_canvas_element_window_handle(self),
        (size_t)(__bridge void *)self, (size_t)(__bridge void *)value);
    if (native == 0) return;
    NSString *stringValue = elisa_appkit_canvas_string(native);
    NSNumber *numberValue = stringValue == nil ? elisa_appkit_canvas_number(native) : nil;
    if (stringValue != nil) {
        [super setAccessibilityValue:stringValue];
    } else if (numberValue != nil) {
        [super setAccessibilityValue:numberValue];
    }
    CFRelease((CFTypeRef)(void *)native);
}
- (void)setAccessibilitySelectedTextRange:(NSRange)value {
    if (elisa_appkit_canvas_set_selected_range(elisa_appkit_canvas_element_window_handle(self),
                                               (size_t)(__bridge void *)self,
                                               value.location, value.length) != 0) {
        [super setAccessibilitySelectedTextRange:value];
    }
}
- (void)elisaSetAccessibilityValue:(id)value {
    [super setAccessibilityValue:value];
}
- (void)elisaSetAccessibilitySelectedTextRange:(NSRange)value {
    [super setAccessibilitySelectedTextRange:value];
}
- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag
             point:(NSPoint)point userData:(void *)data {
    (void)view; (void)tag; (void)point; (void)data;
    // Tooltip ownership and eligibility live in Elisa's retained semantic
    // state. Cocoa only validates the returned object and transfers the
    // temporary +1 into ARC for the protocol's return value.
    // The protocol's `view` argument is supplied by Cocoa, but bridge tests
    // and some AppKit paths may pass the owner through an untyped callback
    // slot. Resolve the identity from the element's retained parent instead
    // of messaging that borrowed argument as though it were an NSView.
    size_t windowHandle = elisa_appkit_canvas_element_window_handle(self);
    size_t native = elisa_appkit_canvas_accessibility_tooltip_text(
        windowHandle, (size_t)(__bridge void *)self);
    // NSViewToolTipOwner declares this return value nonnull. An empty string
    // is Cocoa's no-tooltip result, so keep the protocol contract intact when
    // Elisa has no eligible semantic help text.
    if (native == 0) return @"";
    NSString *value = elisa_appkit_canvas_string(native);
    if (value == nil) {
        CFRelease((CFTypeRef)(void *)native);
        return @"";
    }
    return CFBridgingRelease((CFTypeRef)(void *)native);
}
@end

@interface ElisaCanvasView : NSView <NSTextInputClient, NSUserInterfaceValidations>
@end

static NSWindow *elisa_appkit_canvas_window(size_t handle) {
    if (handle == 0) return nil;
    id object = (__bridge id)(void *)handle;
    return [object isKindOfClass:[NSWindow class]] ? (NSWindow *)object : nil;
}

// NSWindow strongly retains its content view. Resolve it from Elisa's explicit
// window handle so the shim does not keep a duplicate global owner for the
// native view.
static ElisaCanvasView *elisa_appkit_canvas_view(size_t handle) {
    NSWindow *window = elisa_appkit_canvas_window(handle);
    NSView *view = window == nil ? nil : [window contentView];
    return [view isKindOfClass:[ElisaCanvasView class]] ? (ElisaCanvasView *)view : nil;
}

// FFI strings are borrowed opaque Objective-C objects. Validate their dynamic
// type once at the boundary so a non-string handle cannot reach an NSString
// initializer, menu setter, or pasteboard API.
static NSString *elisa_appkit_canvas_string(size_t handle) {
    if (handle == 0) return nil;
    id object = (__bridge id)(void *)handle;
    return [object isKindOfClass:[NSString class]] ? object : nil;
}

static NSCursor *elisa_appkit_canvas_cursor(size_t handle) {
    if (handle == 0) return nil;
    id object = (__bridge id)(void *)handle;
    return [object isKindOfClass:[NSCursor class]] ? object : nil;
}

// Key interpretation receives a retained CFArray created by Elisa from the
// view's borrowed NSEvent handle. Validate both the collection and its single
// event before handing it back to AppKit; malformed cross-boundary data must be
// a no-op, never an Objective-C message to an arbitrary object.
static NSEvent *elisa_appkit_canvas_event(size_t handle) {
    if (handle == 0) return nil;
    id object = (__bridge id)(void *)handle;
    return [object isKindOfClass:[NSEvent class]] ? object : nil;
}

static NSArray *elisa_appkit_canvas_event_array(size_t handle) {
    if (handle == 0) return nil;
    id object = (__bridge id)(void *)handle;
    return [object isKindOfClass:[NSArray class]] ? object : nil;
}

// Accessibility elements retain their parent view, not a duplicate window
// owner. Resolve the current native identity at callback time so an element
// from a retired window cannot authorize an action against a replacement
// session merely because its allocator address was reused.
static size_t elisa_appkit_canvas_element_window_handle(ElisaAccessibilityElement *element) {
    if (element == nil) return 0;
    id parent = [element accessibilityParent];
    if (![parent isKindOfClass:[NSView class]]) return 0;
    NSWindow *window = [(NSView *)parent window];
    return window == nil ? 0 : (size_t)(__bridge void *)window;
}

@interface ElisaCanvasDelegate : NSObject <NSWindowDelegate>
@end
@implementation ElisaCanvasDelegate
- (void)windowWillClose:(NSNotification *)notification {
    id object = notification.object;
    NSWindow *window = [object isKindOfClass:[NSWindow class]] ? (NSWindow *)object : nil;
    // Pass the native identity through unchanged. Elisa decides whether this
    // close belongs to the live session; a late notification from an older
    // window must not stop a replacement session.
    elisa_appkit_canvas_window_closed(window == nil ? 0 : (size_t)(__bridge void *)window);
}
- (void)windowDidResignKey:(NSNotification *)notification {
    id object = notification.object;
    NSWindow *window = [object isKindOfClass:[NSWindow class]] ? (NSWindow *)object : nil;
    elisa_appkit_canvas_focus_changed(window == nil ? 0 : (size_t)(__bridge void *)window, 0);
}
- (void)windowDidBecomeKey:(NSNotification *)notification {
    id object = notification.object;
    NSWindow *window = [object isKindOfClass:[NSWindow class]] ? (NSWindow *)object : nil;
    elisa_appkit_canvas_focus_changed(window == nil ? 0 : (size_t)(__bridge void *)window, 1);
}
- (void)windowDidMove:(NSNotification *)notification {
    id object = notification.object;
    NSWindow *window = [object isKindOfClass:[NSWindow class]] ? (NSWindow *)object : nil;
    elisa_appkit_canvas_accessibility_environment_changed(window == nil ? 0 : (size_t)(__bridge void *)window);
}
- (void)windowDidChangeBackingProperties:(NSNotification *)notification {
    id object = notification.object;
    NSWindow *window = [object isKindOfClass:[NSWindow class]] ? (NSWindow *)object : nil;
    elisa_appkit_canvas_accessibility_environment_changed(window == nil ? 0 : (size_t)(__bridge void *)window);
}
@end
void elisa_appkit_canvas_interpret_key_event(size_t event, size_t windowHandle) {
    NSArray *events = elisa_appkit_canvas_event_array(event);
    ElisaCanvasView *view = elisa_appkit_canvas_view(windowHandle);
    if (events == nil || events.count != 1 || view == nil) return;
    id candidate = [events objectAtIndex:0];
    NSEvent *nativeEvent = elisa_appkit_canvas_event((size_t)(__bridge void *)candidate);
    if (nativeEvent != nil) [view interpretKeyEvents:events];
}

@implementation ElisaCanvasView
- (BOOL)isFlipped { return elisa_appkit_canvas_view_is_flipped() != 0; }
- (BOOL)acceptsFirstResponder { return elisa_appkit_canvas_view_accepts_first_responder() != 0; }
- (BOOL)isAccessibilityElement { return elisa_appkit_canvas_view_is_accessibility_element() != 0; }
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
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    elisa_appkit_canvas_frame(windowHandle, (size_t)context);
}
- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    elisa_appkit_canvas_resize(windowHandle, size.width, size.height);
}
- (NSPoint)eventPoint:(NSEvent *)event {
    return [self convertPoint:[event locationInWindow] fromView:nil];
}
- (void)resetCursorRects {
    [super resetCursorRects];
    // Cursor eligibility, geometry and native cursor selection live in Elisa;
    // Cocoa only clears its transient regions and asks the framework to add
    // the resolved rectangles through the narrow FFI primitive below.
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    elisa_appkit_canvas_rebuild_cursor_rects(windowHandle);
}
- (void)forwardMouseButton:(NSEvent *)event down:(BOOL)down button:(int)button {
    NSPoint p = [self eventPoint:event];
    // The native view reports raw button facts. Elisa decides which framework
    // events a press/release produces and preserves the press-side text-click
    // ordering; this adapter only supplies Cocoa's coordinate and click data.
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    elisa_appkit_canvas_pointer_button(windowHandle, p.x, p.y, button, down, (int)event.clickCount);
}
- (void)mouseMoved:(NSEvent *)event {
    NSPoint p = [self eventPoint:event];
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    NSCursor *nativeCursor = elisa_appkit_canvas_cursor(elisa_appkit_canvas_pointer_move_event(windowHandle, p.x, p.y));
    if (nativeCursor != nil) [nativeCursor set];
}
- (void)mouseEntered:(NSEvent *)event { [self mouseMoved:event]; }
- (void)mouseDragged:(NSEvent *)event { [self mouseMoved:event]; }
- (void)rightMouseDragged:(NSEvent *)event { [self mouseMoved:event]; }
- (void)otherMouseDragged:(NSEvent *)event { [self mouseMoved:event]; }
- (void)mouseDown:(NSEvent *)event { [self forwardMouseButton:event down:YES button:(int)event.buttonNumber]; }
- (void)rightMouseDown:(NSEvent *)event { [self forwardMouseButton:event down:YES button:(int)event.buttonNumber]; }
- (void)otherMouseDown:(NSEvent *)event { [self forwardMouseButton:event down:YES button:(int)event.buttonNumber]; }
- (void)mouseUp:(NSEvent *)event { [self forwardMouseButton:event down:NO button:(int)event.buttonNumber]; }
- (void)rightMouseUp:(NSEvent *)event { [self forwardMouseButton:event down:NO button:(int)event.buttonNumber]; }
- (void)otherMouseUp:(NSEvent *)event { [self forwardMouseButton:event down:NO button:(int)event.buttonNumber]; }
- (void)mouseExited:(NSEvent *)event {
    (void)event;
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    NSCursor *cursor = elisa_appkit_canvas_cursor(elisa_appkit_canvas_pointer_leave_event(windowHandle));
    if (cursor != nil) [cursor set];
}
- (void)scrollWheel:(NSEvent *)event {
    NSPoint p = [self eventPoint:event];
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    elisa_appkit_canvas_pointer_scroll(windowHandle, p.x, p.y, [event scrollingDeltaX], [event scrollingDeltaY]);
}
- (void)keyDown:(NSEvent *)event {
    NSString *chars = [event charactersIgnoringModifiers];
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    elisa_appkit_canvas_key_down_event(windowHandle, (size_t)(__bridge void *)event, event.keyCode,
                                       (size_t)(__bridge void *)chars, (size_t)[event modifierFlags]);
}
- (void)keyUp:(NSEvent *)event {
    NSString *chars = [event charactersIgnoringModifiers];
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    elisa_appkit_canvas_key_up(windowHandle, event.keyCode, (size_t)(__bridge void *)chars);
}
- (void)insertText:(id)input replacementRange:(NSRange)replacementRange {
    // NSTextInputClient permits NSString or NSAttributedString. Pass the
    // borrowed protocol object through unchanged; Elisa classifies and
    // extracts its plain string through CoreFoundation FFI.
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    elisa_appkit_canvas_commit_text(windowHandle, (size_t)(__bridge void *)input,
                                    replacementRange.location, replacementRange.length);
}
- (void)doCommandBySelector:(SEL)selector {
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    elisa_appkit_canvas_text_selector_handle(windowHandle, (size_t)(void *)selector);
}
- (void)selectAll:(id)sender {
    (void)sender;
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    elisa_appkit_canvas_text_action_selector(windowHandle, (size_t)(void *)_cmd);
}
- (void)undo:(id)sender {
    (void)sender;
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    elisa_appkit_canvas_text_action_selector(windowHandle, (size_t)(void *)_cmd);
}
- (void)redo:(id)sender {
    (void)sender;
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    elisa_appkit_canvas_text_action_selector(windowHandle, (size_t)(void *)_cmd);
}
- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    return elisa_appkit_canvas_text_action_valid_selector(windowHandle, (size_t)(void *)item.action) != 0;
}
- (void)copy:(id)sender {
    (void)sender;
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    elisa_appkit_canvas_text_action_selector(windowHandle, (size_t)(void *)_cmd);
}
- (void)cut:(id)sender {
    (void)sender;
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    elisa_appkit_canvas_text_action_selector(windowHandle, (size_t)(void *)_cmd);
}
- (void)paste:(id)sender {
    (void)sender;
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    elisa_appkit_canvas_text_action_selector(windowHandle, (size_t)(void *)_cmd);
}
- (BOOL)hasMarkedText {
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    return elisa_appkit_canvas_has_marked_text(windowHandle) != 0;
}
- (NSRange)markedRange {
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    return NSMakeRange(elisa_appkit_canvas_marked_location(windowHandle),
                       elisa_appkit_canvas_marked_length(windowHandle));
}
- (NSRange)selectedRange {
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    return NSMakeRange(elisa_appkit_canvas_selection_location(windowHandle),
                       elisa_appkit_canvas_selection_length(windowHandle));
}
- (void)setMarkedText:(id)text selectedRange:(NSRange)selectedRange replacementRange:(NSRange)replacementRange {
    // Elisa performs the same NSString/NSAttributedString normalization for
    // marked text, keeping this protocol adapter object-agnostic.
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    elisa_appkit_canvas_update_marked_text(windowHandle, (size_t)(__bridge void *)text,
                                           selectedRange.location, selectedRange.length,
                                           replacementRange.location, replacementRange.length);
}
- (void)unmarkText {
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    elisa_appkit_canvas_unmark_text(windowHandle);
}
- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText {
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    size_t native = elisa_appkit_canvas_valid_marked_attributes(windowHandle);
    // NSTextInputClient declares a nonnull array. Elisa normally returns an
    // empty retained CFArray; preserve that contract even if allocation fails.
    return native == 0 ? [NSArray array] : CFBridgingRelease((CFTypeRef)(void *)native);
}
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
    size_t actualLocation = elisa_appkit_canvas_not_found;
    size_t actualLength = 0;
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    size_t native = elisa_appkit_canvas_attributed_substring(windowHandle, range.location, range.length,
                                                             &actualLocation, &actualLength);
    if (native == 0) return nil;
    if (actualRange != NULL) *actualRange = NSMakeRange(actualLocation, actualLength);
    NSAttributedString *result = elisa_appkit_canvas_attributed_string(native);
    if (result == nil) {
        // The Elisa callback transfers a +1 even when the object is not an
        // attributed string. Drop that ownership before failing closed;
        // otherwise a malformed result leaks across the FFI boundary.
        CFRelease((CFTypeRef)(void *)native);
        return nil;
    }
    return CFBridgingRelease((CFTypeRef)(void *)native);
}
- (NSUInteger)characterIndexForPoint:(NSPoint)point {
    if (self.window == nil) return elisa_appkit_canvas_not_found;
    size_t windowHandle = (size_t)(__bridge void *)self.window;
    NSPoint inWindow = [self.window convertPointFromScreen:point];
    NSPoint local = [self convertPoint:inWindow fromView:nil];
    return elisa_appkit_canvas_character_at_x(windowHandle, local.x);
}
- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
    if (self.window == nil) {
        if (actualRange != NULL) *actualRange = NSMakeRange(elisa_appkit_canvas_not_found, 0);
        return NSZeroRect;
    }
    size_t location = 0;
    size_t length = 0;
    float x = 0.0f;
    float y = 0.0f;
    float width = 0.0f;
    float height = 0.0f;
    size_t windowHandle = (size_t)(__bridge void *)self.window;
    if (!elisa_appkit_canvas_first_rect(windowHandle, range.location, range.length,
                                        &location, &length, &x, &y, &width, &height)) {
        if (actualRange != NULL) *actualRange = NSMakeRange(elisa_appkit_canvas_not_found, 0);
        return NSZeroRect;
    }
    if (actualRange != NULL) *actualRange = NSMakeRange(location, length);
    NSRect local = NSMakeRect(x, y, width, height);
    NSRect inWindow = [self convertRect:local toView:nil];
    return [self.window convertRectToScreen:inWindow];
}
- (void)flagsChanged:(NSEvent *)event {
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    elisa_appkit_canvas_raw_flags(windowHandle, event.keyCode, (size_t)[event modifierFlags]);
}
@end

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

size_t elisa_appkit_canvas_schedule_redraw(float delay, size_t run_loop_mode,
                                           size_t windowHandle) {
    NSString *mode = elisa_appkit_canvas_string(run_loop_mode);
    if (mode == nil || elisa_appkit_canvas_window(windowHandle) == nil) return 0;
    // Capture only the opaque root handle in the timer block. The timer is
    // retained by Elisa until delivery/cancellation, so no native view is
    // captured or kept alive by the scheduler.
    NSTimer *timer = [NSTimer timerWithTimeInterval:delay repeats:NO block:^(NSTimer *fired) {
        (void)fired;
        // Timer delivery re-enters Elisa so lifecycle and stale-window policy
        // stay with the retained framework state rather than this block.
        elisa_appkit_canvas_timer_fired(windowHandle);
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

// Elisa owns semantic identity and calls the typed setters immediately after
// adding a node. Return a retained native object for a new element so the
// bridge does not maintain a second identifier lookup table for the in-flight
// frame. Elisa retains each element handle; AppKit's accessibility children
// property retains the currently committed ordered list.
static ElisaAccessibilityElement *elisa_appkit_canvas_element(size_t handle) {
    if (handle == 0) return nil;
    id object = (__bridge id)(void *)handle;
    return [object isKindOfClass:[ElisaAccessibilityElement class]] ? object : nil;
}

static NSNumber *elisa_appkit_canvas_number(size_t handle) {
    if (handle == 0) return nil;
    id object = (__bridge id)(void *)handle;
    return [object isKindOfClass:[NSNumber class]] ? (NSNumber *)object : nil;
}

static NSAttributedString *elisa_appkit_canvas_attributed_string(size_t handle) {
    if (handle == 0) return nil;
    id object = (__bridge id)(void *)handle;
    return [object isKindOfClass:[NSAttributedString class]] ? (NSAttributedString *)object : nil;
}

size_t elisa_appkit_canvas_accessibility_add(size_t windowHandle, size_t previousHandle,
                                            int isNew, size_t identifierString, size_t role,
                                            size_t subrole,
                                            size_t label, size_t help,
                                            float x, float y, float width, float height,
                                            int enabled, int focused) {
    ElisaCanvasView *view = elisa_appkit_canvas_view(windowHandle);
    if (label == 0 || view == nil) return 0;
    NSString *labelValue = elisa_appkit_canvas_string(label);
    if (labelValue == nil) return 0;
    NSString *helpValue = help == 0 ? nil : elisa_appkit_canvas_string(help);
    NSString *identifierValue = identifierString == 0 ? nil : elisa_appkit_canvas_string(identifierString);
    NSAccessibilityRole roleValue = role == 0 ? nil : (NSAccessibilityRole)elisa_appkit_canvas_string(role);
    NSAccessibilitySubrole subroleValue = subrole == 0 ? nil : (NSAccessibilitySubrole)elisa_appkit_canvas_string(subrole);
    if (role != 0 && roleValue == nil) return 0;
    if (subrole != 0 && subroleValue == nil) return 0;
    if (help != 0 && helpValue == nil) return 0;
    if (identifierString != 0 && identifierValue == nil) return 0;
    // Resolve the owning window before allocating a new element. The view is
    // normally backed by this window, but a close notification can race a
    // late accessibility rebuild; validating first keeps that failure path
    // leak-free.
    NSWindow *window = elisa_appkit_canvas_window(windowHandle);
    if (window == nil) return 0;
    ElisaAccessibilityElement *element = nil;
    if (isNew != 0) {
        element = [ElisaAccessibilityElement new];
        element.accessibilityParent = view;
    } else {
        // Elisa owns semantic identity and explicitly tells the bridge whether
        // this slot is new. A missing reused handle therefore fails closed
        // instead of silently creating a second element for the same node.
        element = elisa_appkit_canvas_element(previousHandle);
        if (element == nil) return 0;
    }
    NSRect local = NSMakeRect(x, y, width, height);
    element.accessibilityRole = roleValue;
    element.accessibilitySubrole = subroleValue;
    element.accessibilityLabel = labelValue;
    element.accessibilityHelp = helpValue;
    element.accessibilityIdentifier = identifierValue;
    element.accessibilityEnabled = enabled != 0;
    element.accessibilityFocused = focused != 0;
    NSRect inWindow = [view convertRect:local toView:nil];
    element.accessibilityFrame = [window convertRectToScreen:inWindow];
    // Elisa retains newly-created elements through the returned +1 handle;
    // identity/reuse itself is selected by Elisa from the previous-frame
    // handles rather than by a native semantic-ID dictionary.
    return isNew != 0 ? (size_t)(__bridge_retained void *)element : (size_t)(__bridge void *)element;
}

void elisa_appkit_canvas_accessibility_release(size_t handle) {
    if (handle == 0) return;
    id object = (__bridge id)(void *)handle;
    if (![object isKindOfClass:[ElisaAccessibilityElement class]]) return;
    (void)CFBridgingRelease((CFTypeRef)(void *)handle);
}

// Value slots are reused across semantic frames. Elisa owns the role/value
// transition policy and calls this primitive only when a node changes value
// kind (or is first created); Cocoa only clears the typed properties.
void elisa_appkit_canvas_accessibility_clear_value(size_t handle,
                                                   size_t selectionLocation,
                                                   size_t selectionLength) {
    ElisaAccessibilityElement *element = elisa_appkit_canvas_element(handle);
    if (element == nil) return;
    [element elisaSetAccessibilityValue:nil];
    element.accessibilitySelectedText = nil;
    [element elisaSetAccessibilitySelectedTextRange:NSMakeRange(selectionLocation, selectionLength)];
    element.accessibilityMinValue = nil;
    element.accessibilityMaxValue = nil;
}

void elisa_appkit_canvas_accessibility_add_tooltip(size_t windowHandle, size_t handle,
                                                   float x, float y, float width, float height) {
    ElisaAccessibilityElement *element = elisa_appkit_canvas_element(handle);
    ElisaCanvasView *view = elisa_appkit_canvas_view(windowHandle);
    if (element == nil || view == nil) return;
    [view addToolTipRect:NSMakeRect(x, y, width, height) owner:element userData:NULL];
}

void elisa_appkit_canvas_accessibility_set_boolean_value(size_t handle, size_t valueHandle) {
    ElisaAccessibilityElement *element = elisa_appkit_canvas_element(handle);
    if (element == nil) return;
    NSNumber *value = elisa_appkit_canvas_number(valueHandle);
    if (value != nil) [element elisaSetAccessibilityValue:value];
}

void elisa_appkit_canvas_accessibility_set_range_values(size_t handle, size_t valueHandle,
                                                        size_t minimumHandle, size_t maximumHandle) {
    ElisaAccessibilityElement *element = elisa_appkit_canvas_element(handle);
    if (element == nil) return;
    NSNumber *valueObject = elisa_appkit_canvas_number(valueHandle);
    NSNumber *minimumObject = elisa_appkit_canvas_number(minimumHandle);
    NSNumber *maximumObject = elisa_appkit_canvas_number(maximumHandle);
    if (valueObject != nil && minimumObject != nil && maximumObject != nil) {
        [element elisaSetAccessibilityValue:valueObject];
        element.accessibilityMinValue = minimumObject;
        element.accessibilityMaxValue = maximumObject;
    }
}

void elisa_appkit_canvas_accessibility_set_text(size_t handle,
                                                 size_t textValue, size_t selectedTextValue,
                                                 size_t selectionLocation, size_t selectionLength) {
    ElisaAccessibilityElement *element = elisa_appkit_canvas_element(handle);
    if (element == nil) return;
    NSString *value = elisa_appkit_canvas_string(textValue);
    NSString *selected = elisa_appkit_canvas_string(selectedTextValue);
    if (value == nil || selected == nil) return;
    [element elisaSetAccessibilityValue:value];
    [element elisaSetAccessibilitySelectedTextRange:NSMakeRange(selectionLocation, selectionLength)];
    element.accessibilitySelectedText = selected;
}

void elisa_appkit_canvas_accessibility_commit(size_t windowHandle, size_t childrenHandle) {
    if (childrenHandle == 0) return;
    id object = (__bridge id)(void *)childrenHandle;
    if (![object isKindOfClass:[NSArray class]]) return;
    NSArray *children = (NSArray *)object;
    ElisaCanvasView *view = elisa_appkit_canvas_view(windowHandle);
    if (view == nil) return;
    [view setAccessibilityChildren:children];
    [view setAccessibilityChildrenInNavigationOrder:children];
}

void elisa_appkit_canvas_accessibility_invalidate_cursor_rects(size_t windowHandle) {
    ElisaCanvasView *view = elisa_appkit_canvas_view(windowHandle);
    if (view == nil) return;
    [[view window] invalidateCursorRectsForView:view];
}

// The view is retained by its window. Return a borrowed opaque handle so
// Elisa can post the layout notification through AppKit's C ABI directly.
size_t elisa_appkit_canvas_accessibility_root(size_t windowHandle) {
    ElisaCanvasView *view = elisa_appkit_canvas_view(windowHandle);
    return view == nil ? 0 : (size_t)(__bridge void *)view;
}
