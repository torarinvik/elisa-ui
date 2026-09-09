// Fragment of uikit_shim.m: the root view controller and the application
// delegate.
//
// Both are pure adapters. The controller reports geometry facts -- size, scale
// and safe-area insets -- once UIKit has laid the view out, and the delegate
// translates UIKit's notification names into the portable lifecycle signals
// Elisa's mobile surface policy already understands.

// Lifecycle signal tokens, matching uikit_lifecycle in the Elisa adapter.
enum {
    ElisaUiKitSignalFocusGained = 0,
    ElisaUiKitSignalFocusLost = 1,
    ElisaUiKitSignalBackground = 2,
    ElisaUiKitSignalForeground = 3,
    ElisaUiKitSignalSurfaceLost = 4,
    ElisaUiKitSignalSurfaceRestored = 5,
    ElisaUiKitSignalStop = 6,
};

static int elisa_uikit_status_bar_hidden = 0;

@interface ElisaUiKitViewController : UIViewController
@property(nonatomic, assign) BOOL elisaStarted;
@end

@implementation ElisaUiKitViewController

- (void)loadView {
    self.view = [[ElisaUiKitView alloc] initWithFrame:CGRectZero];
    self.view.multipleTouchEnabled = NO;
    self.view.opaque = YES;
    [(ElisaUiKitView *)self.view elisaInstallScrollRecognizer];
}

- (BOOL)prefersStatusBarHidden {
    return elisa_uikit_status_bar_hidden != 0;
}

- (void)elisaReportSafeArea {
    UIEdgeInsets insets = self.view.safeAreaInsets;
    elisa_uikit_safe_area_changed((size_t)(__bridge void *)self.view,
                                  (float)insets.top, (float)insets.right,
                                  (float)insets.bottom, (float)insets.left);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    if (size.width <= 0.0 || size.height <= 0.0) return;
    float scale = (float)self.view.window.screen.scale;
    UIEdgeInsets insets = self.view.safeAreaInsets;
    size_t handle = (size_t)(__bridge void *)self.view;
    if (!self.elisaStarted) {
        // The first laid-out frame is the first moment a surface exists. Elisa
        // decides whether that start is accepted; only then does the view
        // become the live session's surface.
        if (elisa_uikit_surface_ready(handle, (float)size.width, (float)size.height, scale,
                                      (float)insets.top, (float)insets.right,
                                      (float)insets.bottom, (float)insets.left) == 0) {
            return;
        }
        self.elisaStarted = YES;
        [self elisaReportAppearance];
        [self elisaObserveTraits];
        return;
    }
    elisa_uikit_surface_resized(handle, (float)size.width, (float)size.height, scale);
}

// Dynamic Type arrives as the scaled size of the body style rather than a
// category name, so Apple's category vocabulary never has to be mirrored here.
- (void)elisaReportAppearance {
    UITraitCollection *traits = self.traitCollection;
    UIFontMetrics *metrics = [UIFontMetrics metricsForTextStyle:UIFontTextStyleBody];
    CGFloat scaledBody = [metrics scaledValueForValue:17.0
                     compatibleWithTraitCollection:traits];
    elisa_uikit_appearance_changed((size_t)(__bridge void *)self.view,
                                   traits.userInterfaceStyle == UIUserInterfaceStyleDark ? 1 : 0,
                                   traits.accessibilityContrast == UIAccessibilityContrastHigh ? 1 : 0,
                                   (float)scaledBody);
}

// Registering for exactly the traits the framework reads means UIKit filters
// the notifications instead of the framework discarding them.
- (void)elisaObserveTraits {
    [self registerForTraitChanges:@[UITraitUserInterfaceStyle.class,
                                    UITraitAccessibilityContrast.class,
                                    UITraitPreferredContentSizeCategory.class]
                      withHandler:^(ElisaUiKitViewController *controller, UITraitCollection *previous) {
        (void)previous;
        if (!controller.elisaStarted) return;
        [controller elisaReportAppearance];
    }];
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    if (!self.elisaStarted) return;
    [self elisaReportSafeArea];
}

@end

@interface ElisaUiKitAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) ElisaUiKitViewController *controller;
@end

@implementation ElisaUiKitAppDelegate

- (size_t)elisaViewHandle {
    if (self.controller == nil) return 0;
    return (size_t)(__bridge void *)self.controller.viewIfLoaded;
}

- (void)elisaObserveKeyboard {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(elisaKeyboardChanged:)
                   name:UIKeyboardWillChangeFrameNotification object:nil];
    [center addObserver:self selector:@selector(elisaKeyboardHidden:)
                   name:UIKeyboardWillHideNotification object:nil];
}

- (void)elisaKeyboardChanged:(NSNotification *)note {
    UIView *view = self.controller.viewIfLoaded;
    if (view == nil) return;
    NSValue *frameValue = note.userInfo[UIKeyboardFrameEndUserInfoKey];
    if (frameValue == nil) return;
    CGRect frame = [view convertRect:[frameValue CGRectValue] fromView:nil];
    CGFloat overlap = CGRectGetMaxY(view.bounds) - CGRectGetMinY(frame);
    // A negative or zero overlap means the keyboard does not cover the view.
    // Reporting the raw number keeps the decision in Elisa, which rejects a
    // malformed inset rather than silently clamping it here.
    elisa_uikit_keyboard_changed((size_t)(__bridge void *)view,
                                 overlap > 0.0 ? (float)overlap : 0.0f,
                                 overlap > 0.0 ? 1 : 0);
}

- (void)elisaKeyboardHidden:(NSNotification *)note {
    (void)note;
    UIView *view = self.controller.viewIfLoaded;
    if (view == nil) return;
    elisa_uikit_keyboard_changed((size_t)(__bridge void *)view, 0.0f, 0);
}

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application;
    (void)launchOptions;
    self.controller = [[ElisaUiKitViewController alloc] init];
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = self.controller;
    [self.window makeKeyAndVisible];
    [self elisaObserveKeyboard];
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    (void)application;
    (void)elisa_uikit_lifecycle([self elisaViewHandle], ElisaUiKitSignalFocusGained);
}

- (void)applicationWillResignActive:(UIApplication *)application {
    (void)application;
    (void)elisa_uikit_lifecycle([self elisaViewHandle], ElisaUiKitSignalFocusLost);
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    (void)application;
    (void)elisa_uikit_lifecycle([self elisaViewHandle], ElisaUiKitSignalBackground);
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    (void)application;
    (void)elisa_uikit_lifecycle([self elisaViewHandle], ElisaUiKitSignalForeground);
}

- (void)applicationWillTerminate:(UIApplication *)application {
    (void)application;
    (void)elisa_uikit_lifecycle([self elisaViewHandle], ElisaUiKitSignalStop);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
