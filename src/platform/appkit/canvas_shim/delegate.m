// Fragment of appkit_canvas_shim.m: the window delegate and key-event interpretation.
// The delegate reports lifecycle facts (close, focus, accessibility environment) to
// Elisa and decides nothing itself.
//
// Not a translation unit of its own: appkit_canvas_shim.m #imports the fragments under
// canvas_shim/ in order so the shim stays ONE compilation unit. That is deliberate --
// the helpers are `static`, the retained Cocoa objects are private state, and
// test/appkit_canvas_bridge_test.m includes the whole unit because identity stability
// of those objects is the behaviour under test. Build scripts compile the umbrella only.

#import <Cocoa/Cocoa.h>

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
