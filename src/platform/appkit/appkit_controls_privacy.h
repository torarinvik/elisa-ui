#import <Cocoa/Cocoa.h>

@interface ElisaAppKitSensitiveTextField : NSTextField
@property(nonatomic, assign) BOOL elisaAccessibilitySensitive;
@end

@interface ElisaAppKitSensitiveSecureTextField : NSSecureTextField
@property(nonatomic, assign) BOOL elisaAccessibilitySensitive;
@end

@interface ElisaAppKitSensitiveButton : NSButton
@property(nonatomic, assign) BOOL elisaAccessibilitySensitive;
@end

@interface ElisaAppKitSensitiveSlider : NSSlider
@property(nonatomic, assign) BOOL elisaAccessibilitySensitive;
@end

@interface ElisaAppKitSensitiveProgressIndicator : NSProgressIndicator
@property(nonatomic, assign) BOOL elisaAccessibilitySensitive;
@end

@interface ElisaAppKitSensitiveFieldEditor : NSTextView
@property(nonatomic, weak) NSView *privacyOwner;
@end

@interface ElisaAppKitPrivacyWindow : NSWindow <NSWindowDelegate>
@property(nonatomic, strong) ElisaAppKitSensitiveFieldEditor *sensitiveFieldEditor;
@end

@interface ElisaAppKitPrivacyPanel : NSPanel <NSWindowDelegate>
@property(nonatomic, strong) ElisaAppKitSensitiveFieldEditor *sensitiveFieldEditor;
@end

void elisa_appkit_set_sensitive_control(NSView *view, BOOL sensitive);
