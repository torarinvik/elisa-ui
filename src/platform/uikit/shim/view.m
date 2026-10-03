// Fragment of uikit_shim.m: ElisaUiKitView.
//
// drawRect: replays Elisa's retained command batch. Touch, press and text
// callbacks each forward one raw fact and let Elisa own the policy: which
// framework event a phase produces, what a HID usage means, and whether the
// software keyboard should be up.

@interface ElisaUiKitView : UIView <UIKeyInput, UIPointerInteractionDelegate> {
    elisa_contact_clock _elisaContactClock;
    NSUInteger _elisaContactCount;
}
// The elements published by the last committed semantic frame. UIKit reads
// this through accessibilityElements; Elisa owns its contents and ordering.
@property(nonatomic, strong) NSArray *elisaElements;
// UITextInput's two stored requirements. The delegate is UIKit's own; the
// tokenizer is the stock one, because word and sentence boundaries in the
// user's language are the text system's job, not the framework's.
@property(nonatomic, weak) id<UITextInputDelegate> inputDelegate;
@property(nonatomic, strong) id<UITextInputTokenizer> elisaTokenizer;
@property(nonatomic, strong) UITextSelectionDisplayInteraction *elisaSelectionDisplay;
@property(nonatomic, assign) size_t elisaSelectionTree;
@property(nonatomic, assign) size_t elisaSelectionField;
@property(nonatomic, strong) UIPanGestureRecognizer *elisaHandlePan;
@property(nonatomic, strong) UIPanGestureRecognizer *elisaFingerScroll;
@property(nonatomic, assign) size_t elisaHandleTree;
@property(nonatomic, assign) size_t elisaHandleField;
@property(nonatomic, assign) BOOL elisaHandleMovingEnd;
@property(nonatomic, strong) UIEditMenuInteraction *elisaEditMenu;
@property(nonatomic, assign) size_t elisaEditTree;
@property(nonatomic, assign) size_t elisaEditField;
- (size_t)elisaHandle;
- (BOOL)elisaPointHitsSelectionHandle:(CGPoint)point;
- (UIView<UITextSelectionHandleView> *)elisaSelectionHandleAtPoint:(CGPoint)point;
@end

@implementation ElisaUiKitView

- (size_t)elisaHandle {
    return (size_t)(__bridge void *)self;
}

- (BOOL)elisaPointHitsSelectionHandle:(CGPoint)point {
    return [self elisaSelectionHandleAtPoint:point] != nil;
}

- (UIView<UITextSelectionHandleView> *)elisaSelectionHandleAtPoint:(CGPoint)point {
    if (!self.elisaSelectionDisplay.isActivated ||
        !elisa_uikit_text_owner_matches([self elisaHandle], self.elisaSelectionTree, self.elisaSelectionField)) return nil;
    for (UIView<UITextSelectionHandleView> *handle in self.elisaSelectionDisplay.handleViews) {
        CGPoint local = [self convertPoint:point toView:handle];
        if (!handle.hidden && handle.alpha > 0.0 && CGRectContainsPoint(handle.bounds, local)) return handle;
    }
    return nil;
}

// Secure fields must not participate in keyboard correction or smart edits.
- (BOOL)isSecureTextEntry {
    return elisa_uikit_text_is_secure([self elisaHandle]) != 0;
}
- (UITextAutocorrectionType)autocorrectionType {
    const int purpose = elisa_uikit_text_purpose([self elisaHandle]);
    return purpose == 0 || purpose == 5 ? UITextAutocorrectionTypeDefault : UITextAutocorrectionTypeNo;
}
- (UIKeyboardType)keyboardType {
    switch (elisa_uikit_text_purpose([self elisaHandle])) {
        case 2: return UIKeyboardTypeEmailAddress;
        case 3: return UIKeyboardTypeURL;
        case 4: return UIKeyboardTypeDecimalPad;
        default: return UIKeyboardTypeDefault;
    }
}
- (UIReturnKeyType)returnKeyType {
    return elisa_uikit_text_purpose([self elisaHandle]) == 5 ? UIReturnKeySearch : UIReturnKeyDefault;
}
- (UITextSpellCheckingType)spellCheckingType {
    return self.secureTextEntry ? UITextSpellCheckingTypeNo : UITextSpellCheckingTypeDefault;
}
- (UITextSmartQuotesType)smartQuotesType {
    return self.secureTextEntry ? UITextSmartQuotesTypeNo : UITextSmartQuotesTypeDefault;
}
- (UITextSmartDashesType)smartDashesType {
    return self.secureTextEntry ? UITextSmartDashesTypeNo : UITextSmartDashesTypeDefault;
}

- (void)drawRect:(CGRect)dirtyRect {
    (void)dirtyRect;
    elisa_uikit_frame([self elisaHandle], (size_t)UIGraphicsGetCurrentContext());
    self.elisaSelectionTree = elisa_uikit_text_owner_tree([self elisaHandle]);
    self.elisaSelectionField = elisa_uikit_text_owner_field([self elisaHandle]);
    self.elisaSelectionDisplay.activated = self.isFirstResponder && self.elisaSelectionTree != 0;
    [self.elisaSelectionDisplay setNeedsSelectionUpdate];
    [self.elisaSelectionDisplay layoutManagedSubviews];
    // Elisa paints themed caret/highlight; UIKit supplies adjustment handles.
    self.elisaSelectionDisplay.cursorView.blinking = NO;
    self.elisaSelectionDisplay.cursorView.alpha = 0.0;
    self.elisaSelectionDisplay.highlightView.alpha = 0.0;
}

// --- Touch -------------------------------------------------------------

- (void)forwardTouches:(NSSet<UITouch *> *)touches phase:(int)phase {
    if (phase == 0 && _elisaContactCount == 0 && touches.count > 0) {
        double first = INFINITY;
        for (UITouch *touch in touches) first = fmin(first, touch.timestamp);
        (void)elisa_contact_seconds(&_elisaContactClock, first, true);
    }
    for (UITouch *touch in touches) {
        const float timestamp = elisa_contact_seconds(&_elisaContactClock,
            touch.timestamp, false);
        if (phase == 0) ++_elisaContactCount;
        if ((phase == 3 || phase == 4) && _elisaContactCount > 0) --_elisaContactCount;
        CGPoint p = [touch locationInView:self];
        if (phase == 0 && [self elisaPointHitsSelectionHandle:p]) {
            [self.elisaEditMenu dismissMenu];
            elisa_uikit_text_handle_contact([self elisaHandle], (size_t)(__bridge void *)touch,
                phase, (float)p.x, (float)p.y, timestamp, (int)touch.type, (int)touch.tapCount,
                self.elisaSelectionTree, self.elisaSelectionField);
            continue;
        }
        elisa_uikit_contact([self elisaHandle], (size_t)(__bridge void *)touch,
                            phase, (float)p.x, (float)p.y, timestamp,
                            (int)touch.type, (int)touch.tapCount);
    }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    [self forwardTouches:touches phase:0];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    [self forwardTouches:touches phase:1];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    [self forwardTouches:touches phase:3];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    [self forwardTouches:touches phase:4];
}

// --- Scrolling ----------------------------------------------------------
//
// A trackpad or mouse attached to an iPad delivers scrolling to a pan gesture
// whose allowedScrollTypesMask includes the indirect types. A finger delivers
// it to a second pan recognizer of its own: UIKit decides when a touch has
// become a drag, and when it does it cancels the touches forwarded above --
// the pressed control releases without activating -- and every update from
// then on arrives here as a scroll delta. A tap stays a tap; a drag scrolls
// whatever viewport is under it. Both recognizers share one handler and one
// Elisa entry, so a finger pan and a wheel are the same event to the widgets.

- (void)elisaInstallScrollRecognizer {
    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(elisaScroll:)];
    pan.allowedScrollTypesMask = UIScrollTypeMaskAll;
    pan.allowedTouchTypes = @[@(UITouchTypeIndirectPointer)];
    [self addGestureRecognizer:pan];
    UIPanGestureRecognizer *finger =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(elisaScroll:)];
    finger.allowedTouchTypes = @[@(UITouchTypeDirect)];
    finger.maximumNumberOfTouches = 1;
    self.elisaFingerScroll = finger;
    [self addGestureRecognizer:finger];
}

- (void)elisaScroll:(UIPanGestureRecognizer *)pan {
    CGPoint delta = [pan translationInView:self];
    if (delta.x == 0.0 && delta.y == 0.0) return;
    // Report each update's own delta, not the accumulated translation.
    [pan setTranslation:CGPointZero inView:self];
    CGPoint at = [pan locationInView:self];
    elisa_uikit_scroll([self elisaHandle], (float)at.x, (float)at.y,
                       (float)delta.x, (float)delta.y);
}

// --- The iPad pointer --------------------------------------------------
//
// A trackpad or mouse does hover, and its pointer changes shape over a
// control. Both reuse the retained policy the macOS canvas already uses: the
// same Move event, and the same cursor tokens.

- (void)elisaInstallPointer {
    UIHoverGestureRecognizer *hover =
        [[UIHoverGestureRecognizer alloc] initWithTarget:self action:@selector(elisaHover:)];
    [self addGestureRecognizer:hover];
    [self addInteraction:[[UIPointerInteraction alloc] initWithDelegate:self]];
}

- (void)elisaHover:(UIHoverGestureRecognizer *)hover {
    if (hover.state == UIGestureRecognizerStateEnded || hover.state == UIGestureRecognizerStateCancelled) {
        elisa_uikit_hover_ended([self elisaHandle]);
        return;
    }
    CGPoint at = [hover locationInView:self];
    elisa_uikit_hover([self elisaHandle], (float)at.x, (float)at.y);
}

- (UIPointerRegion *)pointerInteraction:(UIPointerInteraction *)interaction
                       regionForRequest:(UIPointerRegionRequest *)request
                          defaultRegion:(UIPointerRegion *)defaultRegion {
    (void)interaction;
    float x = 0.0f;
    float y = 0.0f;
    float width = 0.0f;
    float height = 0.0f;
    int token = elisa_uikit_pointer_region([self elisaHandle],
                                           (float)request.location.x, (float)request.location.y,
                                           &x, &y, &width, &height);
    if (token < 0) return defaultRegion;
    // The identifier carries the token back to the style callback, so the
    // region and its appearance are decided by the same lookup.
    return [UIPointerRegion regionWithRect:CGRectMake(x, y, width, height)
                                identifier:@(token)];
}

- (UIPointerStyle *)pointerInteraction:(UIPointerInteraction *)interaction
                        styleForRegion:(UIPointerRegion *)region {
    (void)interaction;
    id identifier = region.identifier;
    if (![identifier isKindOfClass:[NSNumber class]]) return nil;
    int token = [(NSNumber *)identifier intValue];
    if (token == 2) {
        UIPointerShape *beam = [UIPointerShape beamWithPreferredLength:region.rect.size.height
                                                                 axis:UIAxisVertical];
        return [UIPointerStyle styleWithShape:beam constrainedAxes:UIAxisVertical];
    }
    if (token == 1) {
        // Morph the pointer into the control's own shape, which is the
        // iPadOS idiom for something activatable.
        UIPointerShape *shape = [UIPointerShape shapeWithRoundedRect:region.rect];
        return [UIPointerStyle styleWithShape:shape constrainedAxes:UIAxisNeither];
    }
    return nil;
}

// --- Hardware keys -----------------------------------------------------

- (void)forwardPresses:(NSSet<UIPress *> *)presses down:(int)down {
    for (UIPress *press in presses) {
        UIKey *key = press.key;
        if (key == nil) continue;
        elisa_uikit_press([self elisaHandle], (int)key.keyCode, (int64_t)key.modifierFlags, down);
    }
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    [self forwardPresses:presses down:1];
    [super pressesBegan:presses withEvent:event];
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    [self forwardPresses:presses down:0];
    [super pressesEnded:presses withEvent:event];
}

// --- Text input --------------------------------------------------------

- (BOOL)canBecomeFirstResponder {
    return elisa_uikit_wants_keyboard([self elisaHandle]) != 0;
}

- (BOOL)hasText {
    return elisa_uikit_has_text([self elisaHandle]) != 0;
}

- (void)insertText:(NSString *)text {
    [self.elisaEditMenu dismissMenu];
    elisa_uikit_insert_text([self elisaHandle], (size_t)(__bridge void *)text);
}

- (void)deleteBackward {
    [self.elisaEditMenu dismissMenu];
    elisa_uikit_delete_backward([self elisaHandle]);
}

// --- The edit menu -----------------------------------------------------
//
// UIKit asks a responder which standard editing actions it can perform, then
// sends the matching selector. Both questions are forwarded as the opaque SEL:
// Elisa decodes it and answers from the retained text state, so no action
// table or enabled-ness rule lives here.

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (elisa_uikit_text_action_valid_selector([self elisaHandle], (size_t)(void *)action)) return YES;
    return [super canPerformAction:action withSender:sender];
}

- (void)copy:(id)sender {
    (void)sender;
    elisa_uikit_text_action_selector([self elisaHandle], (size_t)(void *)_cmd);
}

- (void)cut:(id)sender {
    (void)sender;
    elisa_uikit_text_action_selector([self elisaHandle], (size_t)(void *)_cmd);
}

- (void)paste:(id)sender {
    (void)sender;
    elisa_uikit_text_action_selector([self elisaHandle], (size_t)(void *)_cmd);
}

- (void)selectAll:(id)sender {
    (void)sender;
    elisa_uikit_text_action_selector([self elisaHandle], (size_t)(void *)_cmd);
}

// --- Semantics ---------------------------------------------------------

- (BOOL)isAccessibilityElement {
    // The view is a container: every semantic node is a child element that
    // Elisa published, never the view itself.
    return NO;
}

- (NSArray *)accessibilityElements {
    NSMutableArray *elements = [self.elisaElements mutableCopy] ?: [NSMutableArray array];
    if (self.elisaSelectionDisplay.isActivated) {
        for (UIView *handle in self.elisaSelectionDisplay.handleViews) {
            if (!handle.hidden && handle.alpha > 0.0) [elements addObject:handle];
        }
    }
    return elements;
}

@end
