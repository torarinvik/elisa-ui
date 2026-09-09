// Fragment of uikit_shim.m: ElisaUiKitView.
//
// drawRect: replays Elisa's retained command batch. Touch, press and text
// callbacks each forward one raw fact and let Elisa own the policy: which
// framework event a phase produces, what a HID usage means, and whether the
// software keyboard should be up.

@interface ElisaUiKitView : UIView <UIKeyInput>
// The elements published by the last committed semantic frame. UIKit reads
// this through accessibilityElements; Elisa owns its contents and ordering.
@property(nonatomic, strong) NSArray *elisaElements;
// UITextInput's two stored requirements. The delegate is UIKit's own; the
// tokenizer is the stock one, because word and sentence boundaries in the
// user's language are the text system's job, not the framework's.
@property(nonatomic, weak) id<UITextInputDelegate> inputDelegate;
@property(nonatomic, strong) id<UITextInputTokenizer> elisaTokenizer;
- (size_t)elisaHandle;
@end

@implementation ElisaUiKitView

- (size_t)elisaHandle {
    return (size_t)(__bridge void *)self;
}

- (void)drawRect:(CGRect)dirtyRect {
    (void)dirtyRect;
    elisa_uikit_frame([self elisaHandle], (size_t)UIGraphicsGetCurrentContext());
}

// --- Touch -------------------------------------------------------------

- (void)forwardTouches:(NSSet<UITouch *> *)touches phase:(int)phase {
    // Elisa's retained model is single-pointer, so the first touch of a set is
    // the pointer. Which touch that is, and what a phase means, are decided
    // there; this only reports the location UIKit measured.
    UITouch *touch = [touches anyObject];
    if (touch == nil) return;
    CGPoint p = [touch locationInView:self];
    elisa_uikit_touch([self elisaHandle], phase, (float)p.x, (float)p.y, (int)touch.tapCount);
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

// --- Indirect scrolling ------------------------------------------------
//
// A trackpad or mouse attached to an iPad delivers scrolling to a pan gesture
// whose allowedScrollTypesMask includes the indirect types. Restricting the
// recognizer to the indirect pointer keeps it from competing with the finger
// touches handled above.

- (void)elisaInstallScrollRecognizer {
    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(elisaScroll:)];
    pan.allowedScrollTypesMask = UIScrollTypeMaskAll;
    pan.allowedTouchTypes = @[@(UITouchTypeIndirectPointer)];
    [self addGestureRecognizer:pan];
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
    elisa_uikit_insert_text([self elisaHandle], (size_t)(__bridge void *)text);
}

- (void)deleteBackward {
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
    return self.elisaElements;
}

@end
