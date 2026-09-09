// Fragment of appkit_canvas_shim.m: ElisaAccessibilityElement, the retained semantic
// object AppKit's accessibility protocol talks to. Every callback forwards the opaque
// element handle to Elisa; slot lookup and widget authorization never live here.
//
// Not a translation unit of its own: appkit_canvas_shim.m #imports the fragments under
// canvas_shim/ in order so the shim stays ONE compilation unit. That is deliberate --
// the helpers are `static`, the retained Cocoa objects are private state, and
// test/appkit_canvas_bridge_test.m includes the whole unit because identity stability
// of those objects is the behaviour under test. Build scripts compile the umbrella only.

#import <Cocoa/Cocoa.h>

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
    size_t windowHandle = elisa_appkit_canvas_element_window_handle(self);
    size_t handle = (size_t)(__bridge void *)self;
    if (elisa_appkit_canvas_set_selected_range(windowHandle, handle,
                                               value.location, value.length) != 0) {
        size_t actualLocation = elisa_appkit_canvas_not_found;
        size_t actualLength = 0;
        // Elisa owns UTF-16 range clamping. Mirror its normalized result so
        // AppKit's retained accessibility state cannot diverge from the
        // framework's text model when a client sends an oversized range.
        if (elisa_appkit_canvas_selected_range(windowHandle, handle,
                                               &actualLocation, &actualLength) != 0) {
            [super setAccessibilitySelectedTextRange:NSMakeRange(actualLocation, actualLength)];
        }
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
