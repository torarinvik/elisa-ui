// Fragment of uikit_shim.m: the C entry points Elisa calls.
//
// Each one performs a single UIKit operation on an object it was handed. No
// decision is taken here: sizes, delays, identity, ordering and text all
// arrive already resolved, and every returned object's ownership is stated at
// the boundary rather than inferred.

static ElisaUiKitView *elisa_uikit_view(size_t handle) {
    if (handle == 0) return nil;
    id object = (__bridge id)(void *)handle;
    return [object isKindOfClass:[ElisaUiKitView class]] ? (ElisaUiKitView *)object : nil;
}

static NSString *elisa_uikit_string(size_t handle) {
    if (handle == 0) return nil;
    id object = (__bridge id)(void *)handle;
    return [object isKindOfClass:[NSString class]] ? (NSString *)object : nil;
}

static ElisaUiKitAccessibilityElement *elisa_uikit_element(size_t handle) {
    if (handle == 0) return nil;
    id object = (__bridge id)(void *)handle;
    return [object isKindOfClass:[ElisaUiKitAccessibilityElement class]]
        ? (ElisaUiKitAccessibilityElement *)object : nil;
}

// --- Application -------------------------------------------------------

// UIKit's scene-aware API has no supported way to reach "the" window from
// outside a scene callback, and this backend deliberately owns exactly one.
// Ask the application for its own delegate rather than keeping a second
// strong reference to UIKit's singleton here.
static ElisaUiKitAppDelegate *elisa_uikit_delegate(void) {
    id delegate = UIApplication.sharedApplication.delegate;
    return [delegate isKindOfClass:[ElisaUiKitAppDelegate class]]
        ? (ElisaUiKitAppDelegate *)delegate : nil;
}

int elisa_uikit_run(void) {
    // UIApplicationMain requires a non-null argument vector even though this
    // backend takes no command line.
    char program[] = "elisa-ui";
    char *arguments[] = {program, NULL};
    return UIApplicationMain(1, arguments, nil, NSStringFromClass([ElisaUiKitAppDelegate class]));
}

void elisa_uikit_stop(void) {
    // iOS has no supported way to terminate an application from inside it, and
    // pretending otherwise would be worse than doing nothing. Release the key
    // window's first responder so the session stops receiving input; the
    // lifecycle transition itself already happened in Elisa.
    [elisa_uikit_delegate().window endEditing:YES];
}

void elisa_uikit_set_status_bar_hidden(int hidden) {
    elisa_uikit_status_bar_hidden = hidden;
    [elisa_uikit_delegate().controller setNeedsStatusBarAppearanceUpdate];
}

void elisa_uikit_set_idle_timer_disabled(int disabled) {
    UIApplication.sharedApplication.idleTimerDisabled = disabled != 0;
}

size_t elisa_uikit_view_handle(void) {
    return (size_t)(__bridge void *)elisa_uikit_delegate().controller.viewIfLoaded;
}

void elisa_uikit_redraw(size_t viewHandle) {
    [elisa_uikit_view(viewHandle) setNeedsDisplay];
}

// --- Redraw timer ------------------------------------------------------

@interface ElisaUiKitTimerTarget : NSObject
@property(nonatomic, assign) size_t viewHandle;
@property(nonatomic, assign) uint32_t generation;
@end

@implementation ElisaUiKitTimerTarget
- (void)fire:(NSTimer *)timer {
    elisa_uikit_timer_fired(self.viewHandle, self.generation, (size_t)(__bridge void *)timer);
}
@end

// Returns a +1 reference Elisa releases through elisa_uikit_cancel_redraw.
size_t elisa_uikit_schedule_redraw(float delay, size_t viewHandle, uint32_t generation) {
    ElisaUiKitTimerTarget *target = [[ElisaUiKitTimerTarget alloc] init];
    target.viewHandle = viewHandle;
    target.generation = generation;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:(NSTimeInterval)delay
                                                     target:target
                                                   selector:@selector(fire:)
                                                   userInfo:nil
                                                    repeats:NO];
    if (timer == nil) return 0;
    return (size_t)CFBridgingRetain(timer);
}

void elisa_uikit_cancel_redraw(size_t handle) {
    if (handle == 0) return;
    NSTimer *timer = (NSTimer *)CFBridgingRelease((CFTypeRef)(void *)handle);
    [timer invalidate];
}

// --- Text input --------------------------------------------------------

int elisa_uikit_begin_text_input(size_t viewHandle) {
    ElisaUiKitView *view = elisa_uikit_view(viewHandle);
    return view != nil && [view becomeFirstResponder] ? 1 : 0;
}

int elisa_uikit_end_text_input(size_t viewHandle) {
    ElisaUiKitView *view = elisa_uikit_view(viewHandle);
    return view != nil && [view resignFirstResponder] ? 1 : 0;
}

void elisa_uikit_reload_input_views(size_t viewHandle) {
    [elisa_uikit_view(viewHandle) reloadInputViews];
}

// --- Pasteboard --------------------------------------------------------

int elisa_uikit_clipboard_write(size_t text) {
    NSString *value = elisa_uikit_string(text);
    if (value == nil) return 0;
    UIPasteboard.generalPasteboard.string = value;
    return 1;
}

// Returns a +1 reference, or 0 when the pasteboard has no string.
size_t elisa_uikit_clipboard_read(void) {
    NSString *value = UIPasteboard.generalPasteboard.string;
    if (value == nil) return 0;
    return (size_t)CFBridgingRetain(value);
}

// --- Semantics ---------------------------------------------------------

int elisa_uikit_accessibility_is_running(void) {
    return (UIAccessibilityIsVoiceOverRunning() || UIAccessibilityIsSwitchControlRunning()) ? 1 : 0;
}

static void elisa_uikit_apply_element(ElisaUiKitAccessibilityElement *element,
                                      size_t identifier, uint64_t traits,
                                      size_t label, size_t hint, size_t value,
                                      float x, float y, float width, float height, int enabled) {
    (void)enabled;
    element.accessibilityIdentifier = elisa_uikit_string(identifier);
    element.accessibilityLabel = elisa_uikit_string(label);
    element.accessibilityHint = elisa_uikit_string(hint);
    element.accessibilityValue = elisa_uikit_string(value);
    // The disabled bit is already part of the traits Elisa computed, so the
    // enabled argument is only the framework's own record of it.
    element.accessibilityTraits = (UIAccessibilityTraits)traits;
    element.accessibilityFrameInContainerSpace = CGRectMake(x, y, width, height);
}

// Returns a +1 reference for a new element, or the reused handle unchanged.
size_t elisa_uikit_accessibility_add(size_t viewHandle, size_t previousHandle, int isNew,
                                     size_t identifier, uint64_t traits,
                                     size_t label, size_t hint, size_t value,
                                     float x, float y, float width, float height, int enabled) {
    ElisaUiKitView *view = elisa_uikit_view(viewHandle);
    if (view == nil) return 0;
    if (isNew == 0) {
        ElisaUiKitAccessibilityElement *reused = elisa_uikit_element(previousHandle);
        if (reused != nil) {
            elisa_uikit_apply_element(reused, identifier, traits, label, hint, value,
                                      x, y, width, height, enabled);
            return previousHandle;
        }
    }
    ElisaUiKitAccessibilityElement *element =
        [[ElisaUiKitAccessibilityElement alloc] initWithAccessibilityContainer:view];
    if (element == nil) return 0;
    element.viewHandle = viewHandle;
    elisa_uikit_apply_element(element, identifier, traits, label, hint, value,
                              x, y, width, height, enabled);
    return (size_t)CFBridgingRetain(element);
}

int elisa_uikit_accessibility_update(size_t viewHandle, size_t handle,
                                     size_t identifier, uint64_t traits,
                                     size_t label, size_t hint, size_t value,
                                     float x, float y, float width, float height, int enabled) {
    (void)viewHandle;
    ElisaUiKitAccessibilityElement *element = elisa_uikit_element(handle);
    if (element == nil) return 0;
    elisa_uikit_apply_element(element, identifier, traits, label, hint, value,
                              x, y, width, height, enabled);
    return 1;
}

void elisa_uikit_accessibility_release(size_t handle) {
    if (handle == 0) return;
    CFRelease((CFTypeRef)(void *)handle);
}

// Elisa builds the ordered child list as an immutable CFArray. This only
// validates and assigns it; it owns no semantic filtering of its own.
int elisa_uikit_accessibility_commit(size_t viewHandle, size_t children) {
    ElisaUiKitView *view = elisa_uikit_view(viewHandle);
    if (view == nil || children == 0) return 0;
    id list = (__bridge id)(void *)children;
    if (![list isKindOfClass:[NSArray class]]) return 0;
    view.elisaElements = (NSArray *)list;
    return 1;
}

void elisa_uikit_accessibility_post_layout_changed(size_t viewHandle) {
    (void)viewHandle;
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil);
}

// Move the assistive cursor to one committed element. Which element, and
// whether the move is warranted at all, are decided in Elisa.
void elisa_uikit_accessibility_focus(size_t viewHandle, size_t handle) {
    (void)viewHandle;
    ElisaUiKitAccessibilityElement *element = elisa_uikit_element(handle);
    if (element == nil) return;
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, element);
}

void elisa_uikit_accessibility_post_screen_changed(size_t viewHandle) {
    (void)viewHandle;
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);
}
