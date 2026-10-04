#import "appkit_controls_privacy.h"
#import <objc/runtime.h>

static BOOL elisa_appkit_is_sensitive(NSView *view);

@implementation ElisaAppKitSensitiveTextField
- (id)accessibilityValue {
    return self.elisaAccessibilitySensitive ? [NSString string] : [super accessibilityValue];
}
@end

@implementation ElisaAppKitSensitiveSecureTextField
- (id)accessibilityValue {
    return self.elisaAccessibilitySensitive ? [NSString string] : [super accessibilityValue];
}
@end

@implementation ElisaAppKitSensitiveButton
- (id)accessibilityValue {
    return self.elisaAccessibilitySensitive ? [NSString string] : [super accessibilityValue];
}
@end

@implementation ElisaAppKitSensitiveSlider
- (id)accessibilityValue {
    return self.elisaAccessibilitySensitive ? [NSString string] : [super accessibilityValue];
}
@end

@implementation ElisaAppKitSensitiveProgressIndicator
- (id)accessibilityValue {
    return self.elisaAccessibilitySensitive ? [NSString string] : [super accessibilityValue];
}
@end

@implementation ElisaAppKitSensitiveFieldEditor
- (BOOL)elisa_owner_is_sensitive {
    return self.privacyOwner != nil && elisa_appkit_is_sensitive(self.privacyOwner);
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
    SEL action = item.action;
    if ((action == @selector(copy:) || action == @selector(cut:)) &&
        [self elisa_owner_is_sensitive]) return NO;
    return [super validateUserInterfaceItem:item];
}

- (void)copy:(id)sender {
    (void)sender;
    if ([self elisa_owner_is_sensitive]) return;
    [super copy:sender];
}

- (void)cut:(id)sender {
    (void)sender;
    if ([self elisa_owner_is_sensitive]) return;
    [super cut:sender];
}

- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pasteboard type:(NSPasteboardType)type {
    if ([self elisa_owner_is_sensitive]) return NO;
    return [super writeSelectionToPasteboard:pasteboard type:type];
}

- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pasteboard types:(NSArray<NSPasteboardType> *)types {
    if ([self elisa_owner_is_sensitive]) return NO;
    return [super writeSelectionToPasteboard:pasteboard types:types];
}
@end

static ElisaAppKitSensitiveFieldEditor *elisa_appkit_sensitive_editor(
    ElisaAppKitSensitiveFieldEditor * __strong *storage, id client) {
    if (![client isKindOfClass:[NSTextField class]] || !elisa_appkit_is_sensitive(client)) return nil;
    if (*storage == nil) *storage = [ElisaAppKitSensitiveFieldEditor fieldEditor];
    (*storage).privacyOwner = client;
    return *storage;
}

@implementation ElisaAppKitPrivacyWindow
- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client {
    (void)sender;
    return elisa_appkit_sensitive_editor(&_sensitiveFieldEditor, client);
}
@end

@implementation ElisaAppKitPrivacyPanel
- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client {
    (void)sender;
    return elisa_appkit_sensitive_editor(&_sensitiveFieldEditor, client);
}
@end

void elisa_appkit_set_sensitive_control(NSView *view, BOOL sensitive) {
    if ([view isKindOfClass:[ElisaAppKitSensitiveTextField class]]) {
        ((ElisaAppKitSensitiveTextField *)view).elisaAccessibilitySensitive = sensitive;
    }
    if ([view isKindOfClass:[ElisaAppKitSensitiveSecureTextField class]]) {
        ((ElisaAppKitSensitiveSecureTextField *)view).elisaAccessibilitySensitive = sensitive;
    }
    if ([view isKindOfClass:[ElisaAppKitSensitiveButton class]]) {
        ((ElisaAppKitSensitiveButton *)view).elisaAccessibilitySensitive = sensitive;
    }
    if ([view isKindOfClass:[ElisaAppKitSensitiveSlider class]]) {
        ((ElisaAppKitSensitiveSlider *)view).elisaAccessibilitySensitive = sensitive;
    }
    if ([view isKindOfClass:[ElisaAppKitSensitiveProgressIndicator class]]) {
        ((ElisaAppKitSensitiveProgressIndicator *)view).elisaAccessibilitySensitive = sensitive;
    }
}

static char elisa_appkit_sensitive_key;
static char elisa_appkit_previous_accessibility_label_key;

static id elisa_appkit_privacy_object(size_t handle) {
    if (handle == 0) return nil;
    return (__bridge id)(void *)handle;
}

static NSString *elisa_appkit_privacy_string(size_t handle) {
    id object = elisa_appkit_privacy_object(handle);
    return [object isKindOfClass:[NSString class]] ? object : nil;
}

static BOOL elisa_appkit_is_sensitive(NSView *view) {
    return [objc_getAssociatedObject(view, &elisa_appkit_sensitive_key) boolValue];
}

void elisa_appkit_set_accessibility_sensitive(size_t handle, int sensitive,
                                             size_t generic_label_handle) {
    NSView *view = (NSView *)elisa_appkit_privacy_object(handle);
    if (![view isKindOfClass:[NSView class]]) return;
    BOOL enabled = sensitive != 0;
    if (elisa_appkit_is_sensitive(view) == enabled) return;
    NSString *genericLabel = elisa_appkit_privacy_string(generic_label_handle);
    if (enabled && genericLabel == nil) return;

    if (enabled) {
        id previous = view.accessibilityLabel ?: (id)[NSNull null];
        objc_setAssociatedObject(view, &elisa_appkit_previous_accessibility_label_key,
                                 previous, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.accessibilityLabel = genericLabel;
        view.accessibilityHelp = nil;
        if ([view isKindOfClass:[NSTextField class]]) {
            NSTextField *field = (NSTextField *)view;
            field.placeholderString = nil;
        }
        elisa_appkit_set_sensitive_control(view, YES);
    } else {
        id previous = objc_getAssociatedObject(view, &elisa_appkit_previous_accessibility_label_key);
        view.accessibilityLabel = previous == [NSNull null] ? nil : previous;
        objc_setAssociatedObject(view, &elisa_appkit_previous_accessibility_label_key,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        elisa_appkit_set_sensitive_control(view, NO);
    }
    objc_setAssociatedObject(view, &elisa_appkit_sensitive_key, @(enabled),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

int elisa_appkit_field_accessibility_is_redacted(size_t handle,
                                                 size_t generic_label_handle) {
    NSTextField *field = (NSTextField *)elisa_appkit_privacy_object(handle);
    NSString *genericLabel = elisa_appkit_privacy_string(generic_label_handle);
    if (![field isKindOfClass:[NSTextField class]] || genericLabel == nil) return 0;
    return elisa_appkit_is_sensitive(field) &&
           [field.accessibilityLabel isEqualToString:genericLabel] &&
           field.accessibilityValue.length == 0 &&
           field.accessibilityHelp.length == 0 &&
           field.placeholderString.length == 0 ? 1 : 0;
}

int elisa_appkit_field_text_matches(size_t handle, size_t text_handle) {
    NSTextField *field = (NSTextField *)elisa_appkit_privacy_object(handle);
    NSString *text = elisa_appkit_privacy_string(text_handle);
    if (![field isKindOfClass:[NSTextField class]] || text == nil) return 0;
    return [field.stringValue isEqualToString:text] ? 1 : 0;
}

int elisa_appkit_accessibility_label_is_nil(size_t handle) {
    NSView *view = (NSView *)elisa_appkit_privacy_object(handle);
    if (![view isKindOfClass:[NSView class]]) return 0;
    return view.accessibilityLabel == nil ? 1 : 0;
}

int elisa_appkit_accessibility_help_is_nil(size_t handle) {
    NSView *view = (NSView *)elisa_appkit_privacy_object(handle);
    if (![view isKindOfClass:[NSView class]]) return 0;
    return view.accessibilityHelp == nil ? 1 : 0;
}
