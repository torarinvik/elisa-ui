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
// The app under test is examples/uikit_smoke: a button, status label and
// custom-canvas text field.

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

    // UIKit's finger-pan recognizer cancels the pending button touch. The
    // app publishes this status only after the retained capture is released.
    XCUICoordinate *start = [button coordinateWithNormalizedOffset:CGVectorMake(0.5, 0.5)];
    XCUICoordinate *end = [start coordinateWithOffset:CGVectorMake(0.0, -120.0)];
    [start pressForDuration:0.05 thenDragToCoordinate:end];
    XCTAssertTrue([app.staticTexts[@"touch cancelled"] waitForExistenceWithTimeout:5.0],
                  @"native touch cancellation did not release retained capture: %@", app.debugDescription);

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
    [app terminate];
}

- (void)testCommittedTextReachesTheRetainedModel {
    XCUIApplication *app = [[XCUIApplication alloc] init];
    app.launchEnvironment = @{@"ELISA_UI_UITEST": @"1"};
    [app launch];

    NSPredicate *namedField = [NSPredicate predicateWithFormat:@"label == %@", @"Name"];
    XCUIElementQuery *allElements = [app descendantsMatchingType:XCUIElementTypeAny];
    XCUIElementQuery *namedFields = [allElements matchingPredicate:namedField];
    XCUIElement *field = namedFields.firstMatch;
    XCTAssertTrue([field waitForExistenceWithTimeout:5.0],
                  @"the framework never published its text input to iOS: %@", app.debugDescription);
    [field tap];
    XCUIElement *keyboard = app.keyboards.firstMatch;
    XCTAssertTrue([keyboard waitForExistenceWithTimeout:5.0],
                  @"tapping the retained text input did not present UIKit's keyboard");
    // The custom-canvas node is a virtual accessibility element, while its
    // containing UIKit view implements UITextInput and owns keyboard focus.
    // Type at the app boundary so XCTest follows that real first responder.
    [app typeText:@"Elisa"];

    NSPredicate *hasCommittedText = [NSPredicate predicateWithFormat:@"value == %@", @"Elisa"];
    XCTNSPredicateExpectation *published =
        [[XCTNSPredicateExpectation alloc] initWithPredicate:hasCommittedText object:field];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[published] timeout:5.0],
                   XCTWaiterResultCompleted,
                   @"committed UIKit text did not return through the retained model and semantic tree");
    [field pressForDuration:1.0];
    XCUIElement *selectAll = app.menuItems[@"Select All"];
    XCTAssertTrue([selectAll waitForExistenceWithTimeout:5.0], @"native edit menu was not presented: %@", app.debugDescription);
    [selectAll tap];
    [app typeText:@"Replaced"];
    XCTNSPredicateExpectation *replaced = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithFormat:@"value == %@", @"Replaced"] object:field];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[replaced] timeout:5.0], XCTWaiterResultCompleted,
                   @"native menu selection was not replaced: %@", field.debugDescription);
    [field pressForDuration:1.0];
    XCTAssertTrue([selectAll waitForExistenceWithTimeout:5.0], @"reopened menu missing: %@", app.debugDescription);
    [selectAll tap];
    XCUIElement *copy = app.menuItems[@"Copy"];
    XCTAssertTrue([copy waitForExistenceWithTimeout:5.0], @"selection did not enable native Copy");
    [copy tap];
    [field pressForDuration:1.0];
    XCTAssertTrue([selectAll waitForExistenceWithTimeout:5.0]);
    [selectAll tap];
    XCUIElement *cut = app.menuItems[@"Cut"];
    XCTAssertTrue([cut waitForExistenceWithTimeout:5.0], @"selection did not enable native Cut");
    [cut tap];
    XCTNSPredicateExpectation *cleared = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithFormat:@"value == %@", @""] object:field];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[cleared] timeout:5.0], XCTWaiterResultCompleted);
    [field pressForDuration:1.0];
    XCUIElement *paste = app.menuItems[@"Paste"];
    XCTAssertTrue([paste waitForExistenceWithTimeout:5.0], @"clipboard text did not enable native Paste");
    [paste tap];
    XCTNSPredicateExpectation *pasted = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithFormat:@"value == %@", @"Replaced"] object:field];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[pasted] timeout:5.0], XCTWaiterResultCompleted);
    XCUIElement *email = [[app descendantsMatchingType:XCUIElementTypeAny]
        matchingPredicate:[NSPredicate predicateWithFormat:@"label == %@", @"Email"]].firstMatch;
    XCTAssertTrue([email waitForExistenceWithTimeout:5.0], @"email-purpose field was not published");
    [email tap];
    XCTAssertTrue([app.keyboards.keys[@"@"] waitForExistenceWithTimeout:5.0],
                  @"switching active fields did not apply the email keyboard purpose");
    [app terminate];
}

- (void)testSecureFieldDoesNotOfferExportActions {
    XCUIApplication *app = [[XCUIApplication alloc] init];
    app.launchEnvironment = @{@"ELISA_UI_UITEST": @"1"};
    [app launch];
    XCUIElement *field = [[app descendantsMatchingType:XCUIElementTypeAny]
        matchingPredicate:[NSPredicate predicateWithFormat:@"label == %@", @"Password"]].firstMatch;
    XCTAssertTrue([field waitForExistenceWithTimeout:5.0]);
    [field tap];
    XCTAssertTrue([app.keyboards.firstMatch waitForExistenceWithTimeout:5.0]);
    [app typeText:@"Secret"];
    XCTAssertTrue([app.staticTexts[@"secure input received"] waitForExistenceWithTimeout:5.0],
                  @"secure input did not reach the retained editor");
    XCTAssertFalse([(NSString *)field.value containsString:@"Secret"], @"secure semantic value leaked plaintext");
    [field pressForDuration:1.0];
    XCUIElement *selectAll = app.menuItems[@"Select All"];
    XCTAssertTrue([selectAll waitForExistenceWithTimeout:5.0], @"secure field did not present its edit menu");
    [selectAll tap];
    XCTAssertFalse(app.menuItems[@"Copy"].exists, @"secure field offered clipboard export");
    XCTAssertFalse(app.menuItems[@"Cut"].exists, @"secure field offered clipboard export through Cut");
    [app terminate];
}

- (void)checkSelectionHandleDragRTL:(BOOL)rtl leading:(BOOL)leading unicode:(BOOL)unicode resume:(BOOL)resume {
    XCUIApplication *app = [[XCUIApplication alloc] init];
    app.launchEnvironment = rtl
        ? @{@"ELISA_UI_UITEST": @"1", @"ELISA_UI_UITEST_RTL": @"1"}
        : @{@"ELISA_UI_UITEST": @"1"};
    if (unicode) app.launchEnvironment = @{@"ELISA_UI_UITEST": @"1", @"ELISA_UI_UITEST_UNICODE": @"1"};
    [app launch];
    XCUIElement *field = [[app descendantsMatchingType:XCUIElementTypeAny]
        matchingPredicate:[NSPredicate predicateWithFormat:@"label == %@", @"Name"]].firstMatch;
    XCTAssertTrue([field waitForExistenceWithTimeout:5.0]);
    [field tap];
    XCTAssertTrue([app.keyboards.firstMatch waitForExistenceWithTimeout:5.0]);
    if (unicode) XCTAssertEqualObjects(field.value, @"á👩‍👩‍👧‍👦bcdefghij");
    else if (!rtl) [app typeText:@"abcdefghij"];
    else XCTAssertEqualObjects(field.value, @"אבגדהוזחטי");
    [field pressForDuration:1.0];
    XCUIElement *selectAll = app.menuItems[@"Select All"];
    XCTAssertTrue([selectAll waitForExistenceWithTimeout:5.0]);
    [selectAll tap];
    XCUIElement *end = [[app descendantsMatchingType:XCUIElementTypeAny]
        matchingIdentifier:leading ? @"com.apple.text.grabber.leading" : @"com.apple.text.grabber.trailing"].firstMatch;
    XCTAssertTrue([end waitForExistenceWithTimeout:5.0], @"native selection handle was not exposed: %@", app.debugDescription);
    XCUICoordinate *from = [end coordinateWithNormalizedOffset:CGVectorMake(0.5, 0.5)];
    // Clear the pan recognition distance even when the handle's dot extends
    // inward from the caret. Stay within the text run, preserving a prefix.
    CGFloat target = unicode ? 0.075 : (leading ? (rtl ? 0.8 : 0.2) : (rtl ? 0.9 : 0.1));
    XCUICoordinate *to = [field coordinateWithNormalizedOffset:CGVectorMake(target, 0.5)];
    [from pressForDuration:0.1 thenDragToCoordinate:to];
    if (unicode) XCTAssertTrue([app.staticTexts[@"unicode prefix selected"] waitForExistenceWithTimeout:5.0],
        @"the native drag did not select the complete combining cluster; value=%@; %@", field.value, app.debugDescription);
    if (resume) {
        [[XCUIDevice sharedDevice] pressButton:XCUIDeviceButtonHome];
        XCTAssertTrue([app waitForState:XCUIApplicationStateRunningBackground timeout:5.0] ||
                      app.state == XCUIApplicationStateRunningBackgroundSuspended);
        [app activate];
        XCTAssertTrue([app waitForState:XCUIApplicationStateRunningForeground timeout:5.0]);
        XCTAssertTrue([app.staticTexts[@"unicode prefix selected"] waitForExistenceWithTimeout:5.0],
                      @"background/resume changed retained selection");
        XCTAssertTrue([end waitForExistenceWithTimeout:5.0], @"selection handles did not return after activation");
        XCTAssertTrue([app.keyboards.firstMatch waitForExistenceWithTimeout:5.0]);
    }
    [app typeText:@"Z"];
    // Moving one endpoint must preserve text outside the selected range,
    // not collapse the caret or replace the entire document.
    NSString *prefix = leading ? (rtl ? @"א" : @"a") : @"Z";
    NSString *suffix = leading ? @"Z" : (rtl ? @"י" : @"j");
    NSPredicate *partial = [NSPredicate predicateWithFormat:
        @"value BEGINSWITH %@ AND value ENDSWITH %@ AND value.length > 1 AND value.length <= 10", prefix, suffix];
    if (unicode) partial = [NSPredicate predicateWithFormat:@"value == %@", @"Z👩‍👩‍👧‍👦bcdefghij"];
    XCTNSPredicateExpectation *changed = [[XCTNSPredicateExpectation alloc] initWithPredicate:partial object:field];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[changed] timeout:5.0], XCTWaiterResultCompleted,
                   @"handle drag did not update the retained selection; value=%@; %@", field.value, field.debugDescription);
    [app terminate];
}

- (void)testSelectionHandleDragChangesRetainedRange {
    [self checkSelectionHandleDragRTL:NO leading:NO unicode:NO resume:NO];
}

- (void)testRTLSelectionHandleDragChangesRetainedRange {
    [self checkSelectionHandleDragRTL:YES leading:NO unicode:NO resume:NO];
}

- (void)testLeadingSelectionHandleDragChangesRetainedRange {
    [self checkSelectionHandleDragRTL:NO leading:YES unicode:NO resume:NO];
}

- (void)testRTLLeadingSelectionHandleDragChangesRetainedRange {
    [self checkSelectionHandleDragRTL:YES leading:YES unicode:NO resume:NO];
}

- (void)testUnicodeSelectionHandlePreservesGraphemes {
    [self checkSelectionHandleDragRTL:NO leading:NO unicode:YES resume:NO];
}

- (void)testUnicodeSelectionSurvivesBackgroundResume {
    [self checkSelectionHandleDragRTL:NO leading:NO unicode:YES resume:YES];
}

@end
