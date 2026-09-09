// UIKit host for elisa-ui's NATIVE-CONTROLS backend.
//
// The sibling of appkit_shim.m, and the opposite of uikit_shim.m: this one
// draws nothing. It creates UILabels, UIButtons, UISliders and UITextFields and
// lets UIKit lay out their text, run the IME, mirror right-to-left and talk to
// VoiceOver. None of that is reachable by drawing rectangles, which is the
// whole reason to want native controls.
//
// A separate translation unit from the canvas shim: the two backends share no
// objects and an application links exactly one of them.
//
// Every function here performs one UIKit operation on values it was handed.
// Which control a widget becomes, where it goes and what state it carries are
// decided in ui_uikit_controls.elisa.

#import <UIKit/UIKit.h>
#include <stdint.h>

// Elisa realizes the control tree once the scene has a surface.
extern int elisa_uikit_controls_realize(size_t rootView, float width, float height,
                                        float safeTop, float safeRight,
                                        float safeBottom, float safeLeft);

@interface ElisaUiKitControlsViewController : UIViewController
@property(nonatomic, assign) CGSize elisaRealizedSize;
@end

@implementation ElisaUiKitControlsViewController
// A rotation or a split-view resize changes the box the tree was laid out
// against, so the tree is realized again rather than left at the old geometry.
// Whether a given size is worth re-realizing is not decided here: the size and
// the insets cross unread, and Elisa answers.
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    if (size.width <= 0.0 || size.height <= 0.0) return;
    if (CGSizeEqualToSize(size, self.elisaRealizedSize)) return;
    UIEdgeInsets insets = self.view.safeAreaInsets;
    if (elisa_uikit_controls_realize((size_t)(__bridge void *)self.view,
                                     (float)size.width, (float)size.height,
                                     (float)insets.top, (float)insets.right,
                                     (float)insets.bottom, (float)insets.left) == 0) {
        return;
    }
    self.elisaRealizedSize = size;
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    // Force the next layout pass to re-realize against the new insets.
    self.elisaRealizedSize = CGSizeZero;
    [self.view setNeedsLayout];
}
@end

@interface ElisaUiKitControlsAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) ElisaUiKitControlsViewController *controller;
@end

@implementation ElisaUiKitControlsAppDelegate
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application;
    (void)launchOptions;
    self.controller = [[ElisaUiKitControlsViewController alloc] init];
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = self.controller;
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int elisa_uikit_controls_run(void) {
    char program[] = "elisa-ui";
    char *arguments[] = {program, NULL};
    return UIApplicationMain(1, arguments, nil,
                             NSStringFromClass([ElisaUiKitControlsAppDelegate class]));
}

// --- Construction ------------------------------------------------------
//
// Each returns a +1 reference Elisa owns until elisa_uikit_controls_release.

static UIView *elisa_uikit_controls_view(size_t handle) {
    if (handle == 0) return nil;
    id object = (__bridge id)(void *)handle;
    return [object isKindOfClass:[UIView class]] ? (UIView *)object : nil;
}

static NSString *elisa_uikit_controls_string(size_t handle) {
    if (handle == 0) return nil;
    id object = (__bridge id)(void *)handle;
    return [object isKindOfClass:[NSString class]] ? (NSString *)object : nil;
}

size_t elisa_uikit_controls_create_view(void) {
    return (size_t)CFBridgingRetain([[UIView alloc] initWithFrame:CGRectZero]);
}

size_t elisa_uikit_controls_create_scroll_view(int vertical, int horizontal) {
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scroll.showsVerticalScrollIndicator = vertical != 0;
    scroll.showsHorizontalScrollIndicator = horizontal != 0;
    return (size_t)CFBridgingRetain(scroll);
}

size_t elisa_uikit_controls_create_label(void) {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    // UIKit owns line breaking and Dynamic Type; this only opts in.
    label.adjustsFontForContentSizeCategory = YES;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    return (size_t)CFBridgingRetain(label);
}

// selectable is what separates a push button from the toggle, check and radio
// kinds: UIKit's own selection behaviour rather than a second state machine.
size_t elisa_uikit_controls_create_button(int selectable) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.configuration = [UIButtonConfiguration plainButtonConfiguration];
    button.changesSelectionAsPrimaryAction = selectable != 0;
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    return (size_t)CFBridgingRetain(button);
}

size_t elisa_uikit_controls_create_text_field(void) {
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.adjustsFontForContentSizeCategory = YES;
    field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    return (size_t)CFBridgingRetain(field);
}

size_t elisa_uikit_controls_create_slider(float low, float high, float value) {
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectZero];
    slider.minimumValue = low;
    slider.maximumValue = high;
    slider.value = value;
    return (size_t)CFBridgingRetain(slider);
}

size_t elisa_uikit_controls_create_progress(void) {
    return (size_t)CFBridgingRetain([[UIProgressView alloc]
        initWithProgressViewStyle:UIProgressViewStyleDefault]);
}

void elisa_uikit_controls_release(size_t handle) {
    if (handle == 0) return;
    CFRelease((CFTypeRef)(void *)handle);
}

// --- Hierarchy and geometry --------------------------------------------

void elisa_uikit_controls_add_child(size_t parent, size_t child) {
    UIView *parentView = elisa_uikit_controls_view(parent);
    UIView *childView = elisa_uikit_controls_view(child);
    if (parentView == nil || childView == nil) return;
    [parentView addSubview:childView];
}

void elisa_uikit_controls_set_frame(size_t handle, float x, float y, float width, float height) {
    elisa_uikit_controls_view(handle).frame = CGRectMake(x, y, width, height);
}

void elisa_uikit_controls_set_content_size(size_t handle, float width, float height) {
    UIView *view = elisa_uikit_controls_view(handle);
    if (![view isKindOfClass:[UIScrollView class]]) return;
    ((UIScrollView *)view).contentSize = CGSizeMake(width, height);
}

// --- Text and state ----------------------------------------------------

void elisa_uikit_controls_set_label_text(size_t handle, size_t text) {
    UIView *view = elisa_uikit_controls_view(handle);
    if ([view isKindOfClass:[UILabel class]]) ((UILabel *)view).text = elisa_uikit_controls_string(text);
}

void elisa_uikit_controls_set_button_title(size_t handle, size_t text) {
    UIView *view = elisa_uikit_controls_view(handle);
    if (![view isKindOfClass:[UIButton class]]) return;
    [(UIButton *)view setTitle:elisa_uikit_controls_string(text) forState:UIControlStateNormal];
}

void elisa_uikit_controls_set_field_text(size_t handle, size_t text) {
    UIView *view = elisa_uikit_controls_view(handle);
    if ([view isKindOfClass:[UITextField class]]) ((UITextField *)view).text = elisa_uikit_controls_string(text);
}

void elisa_uikit_controls_set_button_selected(size_t handle, int selected) {
    UIView *view = elisa_uikit_controls_view(handle);
    if ([view isKindOfClass:[UIButton class]]) ((UIButton *)view).selected = selected != 0;
}

void elisa_uikit_controls_set_slider_state(size_t handle, float low, float high, float value) {
    UIView *view = elisa_uikit_controls_view(handle);
    if (![view isKindOfClass:[UISlider class]]) return;
    UISlider *slider = (UISlider *)view;
    slider.minimumValue = low;
    slider.maximumValue = high;
    slider.value = value;
}

// UIProgressView has no range of its own, so the caller's range is normalized
// in Elisa and this receives the finished fraction.
void elisa_uikit_controls_set_progress(size_t handle, float fraction) {
    UIView *view = elisa_uikit_controls_view(handle);
    if ([view isKindOfClass:[UIProgressView class]]) ((UIProgressView *)view).progress = fraction;
}

void elisa_uikit_controls_set_accessibility_label(size_t handle, size_t text) {
    elisa_uikit_controls_view(handle).accessibilityLabel = elisa_uikit_controls_string(text);
}

// --- Actions -----------------------------------------------------------
//
// One shared target. UIKit reports which control acted and what it now holds;
// Elisa resolves that to a control index, records the value and decides what
// kind of event it was.

extern int elisa_uikit_controls_action(size_t handle, float value, int selected);

@interface ElisaUiKitControlsTarget : NSObject
+ (instancetype)shared;
- (void)controlActed:(id)sender;
@end

@implementation ElisaUiKitControlsTarget
+ (instancetype)shared {
    static ElisaUiKitControlsTarget *target = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        target = [[ElisaUiKitControlsTarget alloc] init];
    });
    return target;
}

- (void)controlActed:(id)sender {
    if (![sender isKindOfClass:[UIControl class]]) return;
    float value = 0.0f;
    int selected = 0;
    if ([sender isKindOfClass:[UISlider class]]) value = ((UISlider *)sender).value;
    if ([sender isKindOfClass:[UIButton class]]) selected = ((UIButton *)sender).selected ? 1 : 0;
    (void)elisa_uikit_controls_action((size_t)(__bridge void *)sender, value, selected);
}
@end

// `valueChange` selects which UIControlEvents to subscribe to. Elisa decides
// it from the widget kind; this only performs the subscription.
void elisa_uikit_controls_set_action(size_t handle, int valueChange) {
    UIView *view = elisa_uikit_controls_view(handle);
    if (![view isKindOfClass:[UIControl class]]) return;
    UIControlEvents events = valueChange != 0 ? UIControlEventValueChanged | UIControlEventEditingChanged
                                              : UIControlEventPrimaryActionTriggered;
    [(UIControl *)view addTarget:[ElisaUiKitControlsTarget shared]
                          action:@selector(controlActed:)
                forControlEvents:events];
}
