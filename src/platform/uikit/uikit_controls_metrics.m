// WHAT THE PLATFORM WANTS, ASKED OF THE PLATFORM.
//
// The measurement half of the UIKit controls bridge, split from the shim for
// the same reason its Elisa counterpart is its own file: the shim reached the
// length this project holds a source to, and measurement is a coherent piece
// of it rather than another page of control plumbing.

#import <UIKit/UIKit.h>
#include <stdint.h>
#include <string.h>

// WHAT THE PLATFORM WANTS, ASKED OF THE PLATFORM.
//
// The framework lays out before a control exists, from numbers its entry point
// supplies -- and on iOS those were invented: a character width guessed at
// (0.55 of the point size), a line height guessed at (1.3), and no idea what a
// button is at its smallest. Android was given real measurements months into
// this and stopped clipping its own words; iOS kept the guesses, and it shows
// the moment Dynamic Type is raised: the text grows, the boxes do not, and
// every caption truncates at once.
//
// THE FONT MEASURED IS THE FONT DRAWN. Every control here uses the preferred
// body font with adjustsFontForContentSizeCategory, so that is what is
// measured -- not the app's requested point size, which no native control
// here honours. Measuring one face and drawing another is how a framework
// gets label boxes that fit nothing.
static UIFont *elisa_uikit_controls_font(int weighted) {
    UIFont *body = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    if (weighted == 0) return body;
    UIFontDescriptor *bold = [body.fontDescriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold];
    return bold == nil ? body : [UIFont fontWithDescriptor:bold size:0.0];
}

float elisa_uikit_controls_measure_text(const char *utf8, int length, float size, int weighted) {
    (void)size;
    if (utf8 == NULL || length <= 0) return 0.0f;
    NSString *text = [[NSString alloc] initWithBytes:utf8 length:(NSUInteger)length encoding:NSUTF8StringEncoding];
    if (text == nil) return 0.0f;
    CGSize measured = [text sizeWithAttributes:@{NSFontAttributeName: elisa_uikit_controls_font(weighted)}];
    return (float)measured.width;
}

// The full line box a UILabel reserves, which is the font's own line height --
// the same distinction Android's textLineHeight draws between the font's
// extent and the tighter ascent-to-descent pair.
float elisa_uikit_controls_line_height(float size) {
    (void)size;
    return (float)elisa_uikit_controls_font(0).lineHeight;
}

// What a control of this kind is at its smallest, asked of a real one and
// remembered: the answer is a property of the type and the text size, not of
// any particular control. The cache is dropped whenever Dynamic Type changes,
// because that is exactly when it stops being true.
static CGFloat elisa_uikit_controls_minimums[16];
static NSString *elisa_uikit_controls_minimums_category = nil;

void elisa_uikit_controls_forget_minimums(void) {
    for (int index = 0; index < 16; index += 1) elisa_uikit_controls_minimums[index] = 0.0;
}

float elisa_uikit_controls_minimum_height(int kind) {
    if (kind < 0 || kind >= 16) return 0.0f;
    NSString *category = UIApplication.sharedApplication.preferredContentSizeCategory;
    if (![category isEqualToString:elisa_uikit_controls_minimums_category]) {
        elisa_uikit_controls_forget_minimums();
        elisa_uikit_controls_minimums_category = category;
    }
    if (elisa_uikit_controls_minimums[kind] > 0.0) return (float)elisa_uikit_controls_minimums[kind];
    UIView *probe = nil;
    switch (kind) {
        case 3: { UILabel *label = [[UILabel alloc] init];
                  label.font = elisa_uikit_controls_font(0);
                  label.text = @"Ag"; probe = label; break; }
        case 4: case 5: case 6: case 7: {
                  UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
                  button.configuration = [UIButtonConfiguration plainButtonConfiguration];
                  [button setTitle:@"Ag" forState:UIControlStateNormal];
                  probe = button; break; }
        case 8: { UITextField *field = [[UITextField alloc] init];
                  field.borderStyle = UITextBorderStyleRoundedRect;
                  field.font = elisa_uikit_controls_font(0);
                  field.text = @"Ag"; probe = field; break; }
        case 9: probe = [[UISlider alloc] init]; break;
        case 10: probe = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault]; break;
        default: return 0.0f;
    }
    CGSize wanted = [probe systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    elisa_uikit_controls_minimums[kind] = wanted.height;
    return (float)wanted.height;
}

// MINIMUM WIDTH, for the kinds that have one.
//
// Height was asked for first because a control that is too short clips its own
// words, which is loud. Width was left to the application until a toggle became
// a UISwitch: a switch is about 51 points wide whatever the box says, so a 34pt
// box the application sized for a painted tick mark cut the switch in half.
// Same lesson as the height, one dimension over -- a native control does not
// shrink to fit, it overflows.
//
// Only the kinds whose width is a property of the CONTROL rather than of its
// text: a switch, a slider's thumb travel, a progress bar. A button or a label
// is as wide as its words, which the layout already measures.
static CGFloat elisa_uikit_controls_min_widths[16];

float elisa_uikit_controls_minimum_width(int kind) {
    if (kind < 0 || kind >= 16) return 0.0f;
    if (elisa_uikit_controls_min_widths[kind] > 0.0) return (float)elisa_uikit_controls_min_widths[kind];
    CGFloat wanted = 0.0;
    switch (kind) {
        case 5: case 6: {
            // A toggle and a check box are a label beside a real UISwitch, so
            // the switch's own width is the floor; the label gets what is left.
            UISwitch *probe = [[UISwitch alloc] init];
            wanted = [probe sizeThatFits:CGSizeZero].width;
            break;
        }
        case 9: {
            UISlider *probe = [[UISlider alloc] init];
            wanted = [probe sizeThatFits:CGSizeZero].width;
            break;
        }
        default: return 0.0f;
    }
    elisa_uikit_controls_min_widths[kind] = wanted;
    return (float)wanted;
}
