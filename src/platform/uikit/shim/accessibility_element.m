// Fragment of uikit_shim.m: the semantic element VoiceOver talks to.
//
// The element is an opaque callback target. It holds no widget identity of its
// own: activation and adjustment forward its address to Elisa, which resolves
// it back to the retained widget through the framework's own history table.

@interface ElisaUiKitAccessibilityElement : UIAccessibilityElement
@property(nonatomic, assign) size_t viewHandle;
@end

@implementation ElisaUiKitAccessibilityElement

- (BOOL)accessibilityActivate {
    return elisa_uikit_accessibility_activate(self.viewHandle, (size_t)(__bridge void *)self) != 0;
}

// UIKit's increment/decrement selectors carry no direction argument. The two
// direction tokens are framework facts, so ask Elisa for them rather than
// spelling +1/-1 here.
- (void)accessibilityIncrement {
    (void)elisa_uikit_accessibility_adjust(self.viewHandle, (size_t)(__bridge void *)self,
                                           elisa_uikit_accessibility_increment_direction());
}

- (void)accessibilityDecrement {
    (void)elisa_uikit_accessibility_adjust(self.viewHandle, (size_t)(__bridge void *)self,
                                           elisa_uikit_accessibility_decrement_direction());
}

@end
