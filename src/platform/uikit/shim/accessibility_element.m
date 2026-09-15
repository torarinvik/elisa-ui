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
// as one leaf. Elisa supplies both ordinary retained children and lazy
// virtual rows, so a node is a leaf only when both child projections are empty.
- (BOOL)isAccessibilityElement {
    size_t handle = (size_t)(__bridge void *)self;
    if (elisa_uikit_accessibility_virtual_count(self.viewHandle, handle) > 0) return NO;
    return elisa_uikit_accessibility_child_count(self.viewHandle, handle) == 0;
}

// A virtual list is a retained UIKit accessibility container even though its
// rows are not retained UIViews. Ordinary groups use the same API and resolve
// their already-committed child handles from Elisa's relationship history.
- (NSInteger)accessibilityElementCount {
    size_t handle = (size_t)(__bridge void *)self;
    int64_t count = elisa_uikit_accessibility_virtual_count(self.viewHandle, handle);
    if (count == 0) count = elisa_uikit_accessibility_child_count(self.viewHandle, handle);
    return count < 0 ? 0 : (NSInteger)count;
}

- (id)accessibilityElementAtIndex:(NSInteger)index {
    if (index < 0) return nil;
    size_t parent = (size_t)(__bridge void *)self;
    int64_t virtualCount = elisa_uikit_accessibility_virtual_count(self.viewHandle, parent);
    size_t handle = 0;
    if (virtualCount > 0 && (int64_t)index < virtualCount) {
        handle = elisa_uikit_accessibility_virtual_element_at(
            self.viewHandle, parent, (int64_t)index);
    } else if (virtualCount == 0) {
        handle = elisa_uikit_accessibility_child_at(self.viewHandle, parent, (int64_t)index);
    }
    return handle == 0 ? nil : (__bridge id)(void *)handle;
}

- (NSInteger)indexOfAccessibilityElement:(id)element {
    if (element == nil) return NSNotFound;
    size_t parent = (size_t)(__bridge void *)self;
    int64_t index = elisa_uikit_accessibility_virtual_index_of(
        self.viewHandle, parent,
        (size_t)(__bridge void *)element);
    if (index != (int64_t)NSNotFound) return (NSInteger)index;
    index = elisa_uikit_accessibility_child_index_of(
        self.viewHandle, parent, (size_t)(__bridge void *)element);
    return index == (int64_t)NSNotFound ? NSNotFound : (NSInteger)index;
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
