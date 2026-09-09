// Fragment of appkit_canvas_shim.m: ElisaCanvasView. drawRect replays Elisa's retained
// command batch; pointer, keyboard, tracking, tooltip, cursor and NSTextInputClient
// callbacks each forward one raw fact and let Elisa own the policy.
//
// Not a translation unit of its own: appkit_canvas_shim.m #imports the fragments under
// canvas_shim/ in order so the shim stays ONE compilation unit. That is deliberate --
// the helpers are `static`, the retained Cocoa objects are private state, and
// test/appkit_canvas_bridge_test.m includes the whole unit because identity stability
// of those objects is the behaviour under test. Build scripts compile the umbrella only.

#import <Cocoa/Cocoa.h>

@implementation ElisaCanvasView
- (BOOL)isFlipped { return elisa_appkit_canvas_view_is_flipped() != 0; }
- (BOOL)acceptsFirstResponder { return elisa_appkit_canvas_view_accepts_first_responder() != 0; }
- (BOOL)isAccessibilityElement { return elisa_appkit_canvas_view_is_accessibility_element() != 0; }
- (NSTrackingAreaOptions)trackingOptions {
    return (NSTrackingAreaOptions)elisa_appkit_canvas_tracking_options();
}
- (void)updateTrackingAreas {
    for (NSTrackingArea *area in [self trackingAreas]) [self removeTrackingArea:area];
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:[self trackingOptions] owner:self userInfo:nil];
    if (area != nil) [self addTrackingArea:area];
    [super updateTrackingAreas];
}
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    CGContextRef context = [[NSGraphicsContext currentContext] CGContext];
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
#if defined(ELISA_UI_USE_SKIA)
    NSRect backing = [self convertRectToBacking:self.bounds];
    const int32_t skiaStatus = elisa_appkit_canvas_skia_present(
        windowHandle, (size_t)context,
        self.bounds.size.width, self.bounds.size.height,
        backing.size.width, backing.size.height);
    if (skiaStatus != 0) {
        // A negative status means Elisa already consumed this frame but the
        // temporary native presentation failed. Do not execute the fallback
        // frame a second time; application callbacks are synchronous and may
        // have changed the retained model.
        return;
    }
#endif
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
// Cocoa answers "which appearance" with a name object, and the accessibility
// variants are separate names. Pass the name through unread, together with the
// two workspace display options; Elisa owns what the combination means.
- (void)reportAppearance {
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    elisa_appkit_canvas_appearance_changed(
        windowHandle, (size_t)(__bridge void *)self.effectiveAppearance.name,
        workspace.accessibilityDisplayShouldIncreaseContrast ? 1 : 0,
        workspace.accessibilityDisplayShouldReduceMotion ? 1 : 0);
}
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self reportAppearance];
}
- (void)accessibilityDisplayOptionsChanged:(NSNotification *)notification {
    (void)notification;
    [self reportAppearance];
}
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window == nil) return;
    // Reduce Motion and Increase Contrast are workspace settings rather than
    // view appearance, so they arrive by notification instead.
    [[NSWorkspace sharedWorkspace].notificationCenter
        addObserver:self
           selector:@selector(accessibilityDisplayOptionsChanged:)
               name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification
             object:nil];
    [self reportAppearance];
}
- (void)dealloc {
    [[NSWorkspace sharedWorkspace].notificationCenter removeObserver:self];
}
- (void)flagsChanged:(NSEvent *)event {
    size_t windowHandle = self.window == nil ? 0 : (size_t)(__bridge void *)self.window;
    elisa_appkit_canvas_raw_flags(windowHandle, event.keyCode, (size_t)[event modifierFlags]);
}
@end
