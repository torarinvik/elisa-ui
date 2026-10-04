// Native-control redaction lives beside UIKit's object boundary. Elisa owns
// the policy bit and supplies the generic label; this file only applies and
// restores those values on the native objects.

#import <objc/runtime.h>

static char elisa_sensitive_key;
static char elisa_sensitive_label_key;
static char elisa_previous_accessibility_label_key;

@interface ElisaUiKitControlsTextField : UITextField
@property(nonatomic, assign) BOOL elisaAccessibilitySensitive;
@end

@implementation ElisaUiKitControlsTextField
- (NSString *)accessibilityValue {
    return self.elisaAccessibilitySensitive ? @"" : [super accessibilityValue];
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (self.elisaAccessibilitySensitive &&
        (action == @selector(copy:) || action == @selector(cut:))) return NO;
    return [super canPerformAction:action withSender:sender];
}
@end

static BOOL elisa_uikit_controls_is_sensitive(UIView *view) {
    return [objc_getAssociatedObject(view, &elisa_sensitive_key) boolValue];
}

static void elisa_uikit_controls_apply_sensitive_to_view(UIView *view,
                                                          BOOL sensitive,
                                                          NSString *genericLabel) {
    if (view == nil || elisa_uikit_controls_is_sensitive(view) == sensitive) return;
    if (sensitive) {
        BOOL derivesLabelFromVisibleText = [view isKindOfClass:[UILabel class]] ||
                                           [view isKindOfClass:[UIButton class]];
        id previous = derivesLabelFromVisibleText ? (id)[NSNull null]
                                                  : (view.accessibilityLabel ?: (id)[NSNull null]);
        objc_setAssociatedObject(view, &elisa_previous_accessibility_label_key,
                                 previous, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &elisa_sensitive_label_key,
                                 genericLabel, OBJC_ASSOCIATION_COPY_NONATOMIC);
        view.accessibilityLabel = genericLabel;
        view.accessibilityValue = @"";
    } else {
        id previous = objc_getAssociatedObject(view, &elisa_previous_accessibility_label_key);
        view.accessibilityLabel = previous == [NSNull null] ? nil : previous;
        view.accessibilityValue = nil;
        objc_setAssociatedObject(view, &elisa_previous_accessibility_label_key,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &elisa_sensitive_label_key,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(view, &elisa_sensitive_key, @(sensitive),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if ([view isKindOfClass:[ElisaUiKitControlsTextField class]]) {
        ((ElisaUiKitControlsTextField *)view).elisaAccessibilitySensitive = sensitive;
    }
}

void elisa_uikit_controls_set_accessibility_sensitive(size_t handle,
                                                       int sensitive,
                                                       size_t genericLabelHandle) {
    NSString *genericLabel = genericLabelHandle == 0 ? nil :
        CFBridgingRelease((CFTypeRef)(void *)genericLabelHandle);
    UIView *view = elisa_uikit_controls_view(handle);
    if (view == nil) return;
    BOOL enabled = sensitive != 0;
    elisa_uikit_controls_apply_sensitive_to_view(view, enabled, genericLabel);
    // A toggle row is one retained control but two native accessibility
    // elements. Redact both children too, leaving their visible text/state
    // and the UIKit interaction unchanged.
    if (view.tag == ELISA_SWITCH_ROW_TAG) {
        for (UIView *child in view.subviews) {
            elisa_uikit_controls_apply_sensitive_to_view(child, enabled, genericLabel);
        }
    }
}

static void elisa_uikit_controls_set_accessibility_label_value(UIView *view,
                                                                NSString *label) {
    if (elisa_uikit_controls_is_sensitive(view)) {
        objc_setAssociatedObject(view, &elisa_previous_accessibility_label_key,
                                 label ?: (id)[NSNull null], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.accessibilityLabel = objc_getAssociatedObject(view, &elisa_sensitive_label_key);
        return;
    }
    view.accessibilityLabel = label;
}

void elisa_uikit_controls_set_accessibility_label(size_t handle, size_t text) {
    UIView *view = elisa_uikit_controls_view(handle);
    elisa_uikit_controls_set_accessibility_label_value(
        view, elisa_uikit_controls_string(text));
}
