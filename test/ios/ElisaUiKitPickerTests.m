// End-to-end UIKit PhotosUI and Files picker smoke.
//
// The test selects a built-in simulator photo and a text file in the smoke app's
// Documents folder. Each selection must return to Elisa, be read through the
// bounded selection API, and be explicitly released by the application.

#import <XCTest/XCTest.h>

@interface ElisaUiKitPickerTests : XCTestCase
@end

@implementation ElisaUiKitPickerTests

- (XCUIElement *)elementNamed:(NSString *)name inApp:(XCUIApplication *)app {
    NSPredicate *named = [NSPredicate predicateWithFormat:@"label == %@ OR identifier == %@", name, name];
    XCUIElementQuery *elements = [app descendantsMatchingType:XCUIElementTypeAny];
    return [[elements matchingPredicate:named] firstMatch];
}

- (void)tapElementNamed:(NSString *)name inApp:(XCUIApplication *)app {
    XCUIElement *element = [self elementNamed:name inApp:app];
    XCTAssertTrue([element waitForExistenceWithTimeout:8.0],
                  @"Missing UI element '%@': %@", name, app.debugDescription);
    XCTAssertTrue(element.isHittable, @"UI element '%@' is not hittable: %@", name, app.debugDescription);
    [element tap];
}

- (void)testPhotoAndFileSelectionsAreReadAndReleased {
    XCUIApplication *app = [[XCUIApplication alloc] init];
    [app launch];

    [self tapElementNamed:@"Choose photo" inApp:app];
    NSPredicate *photoLabel = [NSPredicate predicateWithFormat:@"label BEGINSWITH %@", @"Photo,"];
    XCUIElementQuery *photos = [app.images matchingPredicate:photoLabel];
    XCUIElement *photo = [photos elementBoundByIndex:1];
    XCTAssertTrue([photo waitForExistenceWithTimeout:10.0],
                  @"The system photo picker did not show its simulator library assets: %@", app.debugDescription);
    [photo tap];

    XCUIElement *photoPass = [self elementNamed:@"PHOTO PASS: image bytes read and released" inApp:app];
    XCTAssertTrue([photoPass waitForExistenceWithTimeout:12.0],
                  @"The selected image did not complete the bounded read/release path: %@", app.debugDescription);

    [self tapElementNamed:@"Choose file" inApp:app];
    XCUIElement *browse = [self elementNamed:@"Browse" inApp:app];
    if ([browse waitForExistenceWithTimeout:2.0] && browse.isHittable) [browse tap];
    [self tapElementNamed:@"On My iPhone" inApp:app];
    [self tapElementNamed:@"UIKit Picker Smoke" inApp:app];
    NSPredicate *fileLabel = [NSPredicate predicateWithFormat:@"label BEGINSWITH %@", @"elisa-picker-smoke"];
    XCUIElement *file = [[app.cells matchingPredicate:fileLabel] firstMatch];
    XCTAssertTrue([file waitForExistenceWithTimeout:8.0],
                  @"The Files picker did not show its Documents fixture: %@", app.debugDescription);
    [file tap];

    XCUIElement *open = [self elementNamed:@"Open" inApp:app];
    if ([open waitForExistenceWithTimeout:2.0] && open.isHittable) [open tap];
    XCUIElement *filePass = [self elementNamed:@"FILES PASS: content bytes read and released" inApp:app];
    XCTAssertTrue([filePass waitForExistenceWithTimeout:12.0],
                  @"The selected file did not complete the bounded read/release path: %@", app.debugDescription);
    [app terminate];
}

@end
