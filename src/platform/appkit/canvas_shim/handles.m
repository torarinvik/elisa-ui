// Fragment of appkit_canvas_shim.m: the opaque-handle helpers. Elisa holds Cocoa objects
// as size_t handles; these functions turn a handle back into a typed object, refusing
// anything of the wrong class, so no later code performs an unchecked bridge cast.
//
// Not a translation unit of its own: appkit_canvas_shim.m #imports the fragments under
// canvas_shim/ in order so the shim stays ONE compilation unit. That is deliberate --
// the helpers are `static`, the retained Cocoa objects are private state, and
// test/appkit_canvas_bridge_test.m includes the whole unit because identity stability
// of those objects is the behaviour under test. Build scripts compile the umbrella only.

#import <Cocoa/Cocoa.h>

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

static BOOL elisa_appkit_canvas_accessibility_children_valid(NSArray *children,
                                                              size_t windowHandle) {
    if (children == nil || windowHandle == 0) return NO;
    for (id object in children) {
        if (![object isKindOfClass:[ElisaAccessibilityElement class]]) return NO;
        if (elisa_appkit_canvas_element_window_handle((ElisaAccessibilityElement *)object) != windowHandle) return NO;
    }
    return YES;
}
