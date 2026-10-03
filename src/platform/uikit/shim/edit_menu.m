// UIKit owns menu presentation; Elisa owns action eligibility and editing.
@interface ElisaUiKitView (EditMenu) <UIEditMenuInteractionDelegate, UIGestureRecognizerDelegate>
- (void)elisaInstallEditMenu;
@end

@implementation ElisaUiKitView (EditMenu)

- (void)elisaInstallEditMenu {
    self.elisaEditMenu = [[UIEditMenuInteraction alloc] initWithDelegate:self];
    [self addInteraction:self.elisaEditMenu];
    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(elisaEditMenuPress:)];
    press.delegate = self;
    press.cancelsTouchesInView = NO;
    press.delaysTouchesBegan = NO;
    press.delaysTouchesEnded = NO;
    [self addGestureRecognizer:press];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    CGPoint point = [touch locationInView:self];
    if (recognizer == self.elisaHandlePan) {
        UIView<UITextSelectionHandleView> *handle = [self elisaSelectionHandleAtPoint:point];
        if (handle == nil) return NO;
        [self.elisaEditMenu dismissMenu];
        self.elisaHandleTree = self.elisaSelectionTree;
        self.elisaHandleField = self.elisaSelectionField;
        self.elisaHandleMovingEnd = handle.direction == NSDirectionalRectEdgeTrailing;
        return YES;
    }
    return elisa_uikit_text_interaction_at([self elisaHandle], (float)point.x, (float)point.y) != 0;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    (void)recognizer;
    (void)other;
    return YES;
}

- (void)elisaEditMenuPress:(UILongPressGestureRecognizer *)press {
    if (press.state != UIGestureRecognizerStateBegan) return;
    CGPoint point = [press locationInView:self];
    if (!elisa_uikit_text_interaction_at([self elisaHandle], (float)point.x, (float)point.y)) return;
    self.elisaEditTree = elisa_uikit_text_owner_tree([self elisaHandle]);
    self.elisaEditField = elisa_uikit_text_owner_field([self elisaHandle]);
    [self.elisaEditMenu presentEditMenuWithConfiguration:
        [UIEditMenuConfiguration configurationWithIdentifier:nil sourcePoint:point]];
}

- (UIMenu *)editMenuInteraction:(UIEditMenuInteraction *)interaction
        menuForConfiguration:(UIEditMenuConfiguration *)configuration
        suggestedActions:(NSArray<UIMenuElement *> *)suggestedActions {
    (void)interaction;
    (void)configuration;
    (void)suggestedActions;
    const size_t tree = self.elisaEditTree;
    const size_t field = self.elisaEditField;
    if (!elisa_uikit_text_owner_matches([self elisaHandle], tree, field)) return [UIMenu menuWithChildren:@[]];
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
    __weak ElisaUiKitView *weakView = self;
    for (size_t index = 0; index < elisa_uikit_text_menu_count(); ++index) {
        NSString *name = [NSString stringWithUTF8String:elisa_uikit_text_menu_selector(index)];
        SEL selector = NSSelectorFromString(name);
        if (!elisa_uikit_text_action_valid_selector([self elisaHandle], (size_t)(void *)selector)) continue;
        size_t titleHandle = elisa_uikit_text_menu_title(index);
        if (titleHandle == 0) continue;
        NSString *title = CFBridgingRelease((CFTypeRef)(void *)titleHandle);
        const BOOL keepsOpen = elisa_uikit_text_menu_keeps_open(index) != 0;
        UIAction *action = [UIAction actionWithTitle:NSLocalizedString(title, @"Text edit menu") image:nil identifier:nil
            handler:^(__kindof UIAction *chosen) {
                (void)chosen;
                ElisaUiKitView *view = weakView;
                if (view == nil || !elisa_uikit_text_owner_matches([view elisaHandle], tree, field)) return;
                if (!elisa_uikit_text_action_valid_selector([view elisaHandle], (size_t)(void *)selector)) return;
                [view.inputDelegate selectionWillChange:view];
                if (!elisa_uikit_text_owner_matches([view elisaHandle], tree, field)) return;
                elisa_uikit_text_action_selector([view elisaHandle], (size_t)(void *)selector);
                if (!elisa_uikit_text_owner_matches([view elisaHandle], tree, field)) return;
                [view.inputDelegate selectionDidChange:view];
                if (keepsOpen) [view.elisaEditMenu reloadVisibleMenu];
                else [view.elisaEditMenu dismissMenu];
            }];
        if (keepsOpen) action.attributes = UIMenuElementAttributesKeepsMenuPresented;
        [items addObject:action];
    }
    return [UIMenu menuWithChildren:items];
}
@end
