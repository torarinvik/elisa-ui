// A real touch, delivered by the system.
//
// simctl cannot inject one, so this is an XCUITest: XCUIApplication drives the
// simulator's own HID pipeline, which is the same path a finger takes. That
// makes the assertions below cover the whole chain at once --
//
//   * the semantic tree Elisa publishes is visible to iOS at all (XCUI can
//     only see a custom-painted canvas through its accessibility elements),
//   * UIKit delivers the touch to the view,
//   * the framework routes it into the retained model,
//   * the application callback runs,
//   * the frame is repainted and the new semantics are published.
//
// The app under test is examples/uikit_smoke: one button and one status label.

#import <XCTest/XCTest.h>

@interface ElisaUiKitTouchTests : XCTestCase
@end

@implementation ElisaUiKitTouchTests

- (void)setUp {
    self.continueAfterFailure = NO;
}

- (void)testATouchReachesTheRetainedModel {
    XCUIApplication *app = [[XCUIApplication alloc] init];
    app.launchEnvironment = @{@"ELISA_UI_UITEST": @"1"};
    [app launch];

    // The canvas paints every pixel itself, so anything XCUI can see here came
    // from Elisa's own semantic tree.
    XCUIElement *button = app.buttons[@"Tap me"];
    XCTAssertTrue([button waitForExistenceWithTimeout:5.0],
                  @"the framework never published its button to iOS");
    XCUIElement *waiting = app.staticTexts[@"waiting for a tap"];
    XCTAssertTrue([waiting waitForExistenceWithTimeout:5.0],
                  @"the framework never published its status label to iOS");

    [button tap];

    // A real touch went in; the label the application rewrote must come back
    // out through a repainted, republished semantic tree.
    XCUIElement *tapped = app.staticTexts[@"tapped"];
    XCTAssertTrue([tapped waitForExistenceWithTimeout:5.0],
                  @"a real touch did not reach the retained model");
    XCTAssertFalse(waiting.exists,
                   @"the old status text was still published after the tap");

    // A second touch must be counted too: the framework must not latch after
    // the first one.
    [button tap];
    XCTAssertTrue([app.staticTexts[@"tapped twice"] waitForExistenceWithTimeout:5.0],
                  @"a second touch did not reach the retained model");
}

@end
