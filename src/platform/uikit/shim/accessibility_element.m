// Fragment of uikit_shim.m: the semantic element VoiceOver talks to.
//
// The element is an opaque callback target. It holds no widget identity of its
// own: activation and adjustment forward its address to Elisa, which resolves
// it back to the retained widget through the framework's own history table.

@interface ElisaUiKitAccessibilityElement : UIAccessibilityElement
@property(nonatomic, assign) size_t viewHandle;
@end

@implementation ElisaUiKitAccessibilityElement

// UIKit requires a dynamic accessibility container to opt out of being read
// as one leaf. Ordinary semantic elements still report YES because their
// virtual count is zero and are handled by the committed view container.
- (BOOL)isAccessibilityElement {
    return elisa_uikit_accessibility_virtual_count(
        self.viewHandle, (size_t)(__bridge void *)self) == 0;
}

// A virtual list is a retained UIKit accessibility container even though its
// rows are not retained UIViews. Elisa resolves the logical count and creates
// one bounded proxy only for the row UIKit asks to inspect.
- (NSInteger)accessibilityElementCount {
    int64_t count = elisa_uikit_accessibility_virtual_count(self.viewHandle,
                                                            (size_t)(__bridge void *)self);
    return count < 0 ? 0 : (NSInteger)count;
}

- (id)accessibilityElementAtIndex:(NSInteger)index {
    if (index < 0) return nil;
    size_t handle = elisa_uikit_accessibility_virtual_element_at(
        self.viewHandle, (size_t)(__bridge void *)self, (int64_t)index);
    return handle == 0 ? nil : (__bridge id)(void *)handle;
}

- (NSInteger)indexOfAccessibilityElement:(id)element {
    if (element == nil) return NSNotFound;
    int64_t index = elisa_uikit_accessibility_virtual_index_of(
        self.viewHandle, (size_t)(__bridge void *)self,
        (size_t)(__bridge void *)element);
    return index < 0 ? NSNotFound : (NSInteger)index;
}

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
