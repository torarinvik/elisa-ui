// Fragment of appkit_canvas_shim.m: the accessibility element lifecycle Elisa drives --
// creating, configuring, retargeting, releasing and committing the ordered child list.
//
// Not a translation unit of its own: appkit_canvas_shim.m #imports the fragments under
// canvas_shim/ in order so the shim stays ONE compilation unit. That is deliberate --
// the helpers are `static`, the retained Cocoa objects are private state, and
// test/appkit_canvas_bridge_test.m includes the whole unit because identity stability
// of those objects is the behaviour under test. Build scripts compile the umbrella only.

#import <Cocoa/Cocoa.h>

// Elisa owns semantic identity and stages typed metadata around the child-list
// commit. Return a retained native object for a new element so the
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

// Apply the frame/role metadata for one semantic element. Keeping this as a
// separate primitive lets Elisa stage a replacement tree without mutating
// elements that are still referenced by Cocoa's currently committed list.
static BOOL elisa_appkit_canvas_configure_accessibility_element(
    ElisaAccessibilityElement *element, ElisaCanvasView *view, NSWindow *window,
    size_t identifierString, size_t role, size_t subrole,
    size_t label, size_t help,
    float x, float y, float width, float height,
    int enabled, int focused) {
    if (element == nil || view == nil || window == nil || label == 0) return NO;
    NSString *labelValue = elisa_appkit_canvas_string(label);
    NSString *helpValue = help == 0 ? nil : elisa_appkit_canvas_string(help);
    NSString *identifierValue = identifierString == 0 ? nil : elisa_appkit_canvas_string(identifierString);
    NSAccessibilityRole roleValue = role == 0 ? nil : (NSAccessibilityRole)elisa_appkit_canvas_string(role);
    NSAccessibilitySubrole subroleValue = subrole == 0 ? nil : (NSAccessibilitySubrole)elisa_appkit_canvas_string(subrole);
    if (labelValue == nil) return NO;
    if (role != 0 && roleValue == nil) return NO;
    if (subrole != 0 && subroleValue == nil) return NO;
    if (help != 0 && helpValue == nil) return NO;
    if (identifierString != 0 && identifierValue == nil) return NO;

    element.accessibilityRole = roleValue;
    element.accessibilitySubrole = subroleValue;
    element.accessibilityLabel = labelValue;
    element.accessibilityHelp = helpValue;
    element.accessibilityIdentifier = identifierValue;
    element.accessibilityEnabled = enabled != 0;
    element.accessibilityFocused = focused != 0;
    NSRect local = NSMakeRect(x, y, width, height);
    NSRect inWindow = [view convertRect:local toView:nil];
    element.accessibilityFrame = [window convertRectToScreen:inWindow];
    return YES;
}

size_t elisa_appkit_canvas_accessibility_add(size_t windowHandle, size_t previousHandle,
                                            int isNew, size_t identifierString, size_t role,
                                            size_t subrole,
                                            size_t label, size_t help,
                                            float x, float y, float width, float height,
                                            int enabled, int focused) {
    ElisaCanvasView *view = elisa_appkit_canvas_view(windowHandle);
    if (label == 0 || view == nil) return 0;
    // Preserve the add primitive's fail-closed validation even when this is a
    // reuse probe. Reused elements are not mutated here, but malformed
    // metadata must still prevent a caller from treating the slot as valid.
    if (elisa_appkit_canvas_string(label) == nil) return 0;
    if (help != 0 && elisa_appkit_canvas_string(help) == nil) return 0;
    if (identifierString != 0 && elisa_appkit_canvas_string(identifierString) == nil) return 0;
    if (role != 0 && elisa_appkit_canvas_string(role) == nil) return 0;
    if (subrole != 0 && elisa_appkit_canvas_string(subrole) == nil) return 0;
    // Resolve the owning window before allocating a new element. The view is
    // normally backed by this window, but a close notification can race a
    // late accessibility rebuild; validating first keeps that failure path
    // leak-free.
    NSWindow *window = elisa_appkit_canvas_window(windowHandle);
    if (window == nil) return 0;
    ElisaAccessibilityElement *element = nil;
    if (isNew != 0) {
        element = [ElisaAccessibilityElement new];
        if (element == nil) return 0;
        element.accessibilityParent = view;
    } else {
        // Elisa owns semantic identity and explicitly tells the bridge whether
        // this slot is new. A missing reused handle therefore fails closed
        // instead of silently creating a second element for the same node.
        element = elisa_appkit_canvas_element(previousHandle);
        if (element == nil) return 0;
        // Reuse is valid only within the same native window. A stale element
        // retained by AppKit after teardown must not be repurposed for a new
        // semantic tree merely because Elisa's bounded ID was reused.
        if (elisa_appkit_canvas_element_window_handle(element) != windowHandle) return 0;
        // Existing elements remain untouched until Elisa has committed the
        // replacement child list. The post-commit update primitive applies
        // the staged metadata once failure can no longer leave Cocoa pointing
        // at the previous tree.
        return (size_t)(__bridge void *)element;
    }
    if (!elisa_appkit_canvas_configure_accessibility_element(element, view, window,
            identifierString, role, subrole, label, help,
            x, y, width, height, enabled, focused)) return 0;
    // Elisa retains newly-created elements through the returned +1 handle;
    // identity/reuse itself is selected by Elisa from the previous-frame
    // handles rather than by a native semantic-ID dictionary.
    return isNew != 0 ? (size_t)(__bridge_retained void *)element : (size_t)(__bridge void *)element;
}

// Commit-time metadata update for an element that was already present in the
// previous semantic tree. This is deliberately separate from `add`: the
// replacement child list is installed first, so a validation failure here can
// only reject the new metadata rather than corrupt the still-visible old list.
int elisa_appkit_canvas_accessibility_update(size_t windowHandle, size_t handle,
                                             size_t identifierString, size_t role,
                                             size_t subrole, size_t label, size_t help,
                                             float x, float y, float width, float height,
                                             int enabled, int focused) {
    ElisaCanvasView *view = elisa_appkit_canvas_view(windowHandle);
    ElisaAccessibilityElement *element = elisa_appkit_canvas_element(handle);
    NSWindow *window = elisa_appkit_canvas_window(windowHandle);
    if (view == nil || window == nil || element == nil) return 0;
    if (elisa_appkit_canvas_element_window_handle(element) != windowHandle) return 0;
    return elisa_appkit_canvas_configure_accessibility_element(element, view, window,
        identifierString, role, subrole, label, help,
        x, y, width, height, enabled, focused) ? 1 : 0;
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
    if (element == nil || view == nil ||
        elisa_appkit_canvas_element_window_handle(element) != windowHandle) return;
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

int elisa_appkit_canvas_accessibility_commit(size_t windowHandle, size_t childrenHandle) {
    if (childrenHandle == 0) return 0;
    id object = (__bridge id)(void *)childrenHandle;
    if (![object isKindOfClass:[NSArray class]]) return 0;
    NSArray *children = (NSArray *)object;
    ElisaCanvasView *view = elisa_appkit_canvas_view(windowHandle);
    if (view == nil || !elisa_appkit_canvas_accessibility_children_valid(children, windowHandle)) return 0;
    [view setAccessibilityChildren:children];
    [view setAccessibilityChildrenInNavigationOrder:children];
    return 1;
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
