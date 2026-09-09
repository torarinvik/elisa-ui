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

// VoiceOver rewriting a field's value. Whether this element is a field at all,
// and what the edit does, are decided in Elisa; a refused edit leaves the
// element's spoken value exactly as it was.
- (void)setAccessibilityValue:(NSString *)value {
    if (elisa_uikit_accessibility_set_text(self.viewHandle, (size_t)(__bridge void *)self,
                                           (size_t)(__bridge void *)value) == 0) {
        return;
    }
    [super setAccessibilityValue:value];
}

- (void)accessibilityDecrement {
    (void)elisa_uikit_accessibility_adjust(self.viewHandle, (size_t)(__bridge void *)self,
                                           elisa_uikit_accessibility_decrement_direction());
}

@end
