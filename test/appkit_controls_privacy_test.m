#import <Cocoa/Cocoa.h>
#include <stdint.h>
#include <stdio.h>

size_t elisa_appkit_create_text_field(size_t text);
size_t elisa_appkit_create_label(size_t text);
size_t elisa_appkit_create_secure_text_field(size_t text);
size_t elisa_appkit_create_push_button(int bezel_style, size_t text);
size_t elisa_appkit_create_slider(float low, float high, float value);
size_t elisa_appkit_create_progress_bar(int progress_style, int indeterminate);
size_t elisa_appkit_create_window_with_style(int style, int backing,
                                             float width, float height);
void elisa_appkit_attach_to_window(size_t handle, size_t parent);
void elisa_appkit_set_placeholder(size_t handle, size_t text);
void elisa_appkit_set_accessibility_help(size_t handle, size_t text);
void elisa_appkit_set_accessibility_sensitive(size_t handle, int sensitive,
                                             size_t generic_label);
void elisa_appkit_set_field_text(size_t handle, size_t text);
void elisa_appkit_set_button_state(size_t handle, int state);
void elisa_appkit_set_slider_state(size_t handle, float low, float high, float value);
void elisa_appkit_set_progress_state(size_t handle, float low, float high, float value);
void elisa_appkit_release(size_t handle);

int elisa_appkit_view_is_flipped(void) { return 1; }
int elisa_appkit_controls_action(size_t handle, float value, long state) {
    (void)handle;
    (void)value;
    (void)state;
    return 0;
}

static size_t elisa_test_string_handle(NSString *value) {
    return (size_t)(uintptr_t)(__bridge void *)value;
}

static int elisa_test_expect(BOOL condition, const char *message) {
    if (condition) return 0;
    fprintf(stderr, "appkit-controls-privacy: %s\n", message);
    return 1;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *initial = @"ada";
        NSString *prompt = @"name@example.org";
        NSString *help = @"Private account hint";
        NSString *generic = @"Sensitive content";
        NSString *edited = @"still visible";
        size_t initialHandle = elisa_test_string_handle(initial);
        size_t promptHandle = elisa_test_string_handle(prompt);
        size_t helpHandle = elisa_test_string_handle(help);
        size_t genericHandle = elisa_test_string_handle(generic);
        size_t editedHandle = elisa_test_string_handle(edited);
        size_t handle = elisa_appkit_create_text_field(initialHandle);
        if (handle == 0) return 1;
        NSTextField *field = (__bridge NSTextField *)(void *)handle;
        field.accessibilityLabel = @"Account name";
        elisa_appkit_set_placeholder(handle, promptHandle);
        elisa_appkit_set_accessibility_help(handle, helpHandle);

        int failures = 0;
        failures += elisa_test_expect(field.isEditable && field.isSelectable,
                                      "sensitive-field subclass lost native text editing");
        elisa_appkit_set_accessibility_sensitive(handle, 1, genericHandle);
        failures += elisa_test_expect([field.accessibilityLabel isEqualToString:generic],
                                      "sensitive field label is not generic");
        failures += elisa_test_expect(field.accessibilityValue.length == 0,
                                      "sensitive field exposes an accessibility value");
        failures += elisa_test_expect([field.stringValue isEqualToString:initial],
                                      "redaction changed the visible field value");
        failures += elisa_test_expect(field.placeholderString == nil && field.accessibilityHelp == nil,
                                      "sensitive field retained a prompt or help string");

        elisa_appkit_set_field_text(handle, editedHandle);
        failures += elisa_test_expect(field.accessibilityValue.length == 0 &&
                                          [field.accessibilityLabel isEqualToString:generic],
                                      "editing replaced the active accessibility redaction");
        failures += elisa_test_expect([field.stringValue isEqualToString:edited],
                                      "editing was blocked by accessibility redaction");

        elisa_appkit_set_accessibility_sensitive(handle, 0, 0);
        elisa_appkit_set_placeholder(handle, promptHandle);
        elisa_appkit_set_accessibility_help(handle, helpHandle);
        failures += elisa_test_expect([field.accessibilityLabel isEqualToString:@"Account name"],
                                      "clearing sensitivity did not restore the previous label");
        failures += elisa_test_expect([field.accessibilityValue isEqualToString:edited],
                                      "clearing sensitivity did not restore the accessible value");
        failures += elisa_test_expect([field.placeholderString isEqualToString:prompt] &&
                                          [field.accessibilityHelp isEqualToString:help],
                                      "clearing sensitivity did not restore prompt and help");

        size_t windowHandle = elisa_appkit_create_window_with_style(0, 2, 320.0f, 100.0f);
        if (windowHandle == 0) return 1;
        NSWindow *window = (__bridge NSWindow *)(void *)windowHandle;
        elisa_appkit_attach_to_window(handle, windowHandle);
        elisa_appkit_set_accessibility_sensitive(handle, 1, genericHandle);
        NSText *fieldEditor = [window fieldEditor:YES forObject:field];
        failures += elisa_test_expect([fieldEditor isKindOfClass:[NSTextView class]],
                                      "sensitive AppKit field did not receive a text editor");
        if ([fieldEditor isKindOfClass:[NSTextView class]]) {
            NSTextView *editor = (NSTextView *)fieldEditor;
            [editor setString:field.stringValue];
            [editor setSelectedRange:NSMakeRange(0, 5)];
            failures += elisa_test_expect(editor.selectedRange.length == 5,
                                          "sensitive field editor did not retain its selection");
            failures += elisa_test_expect([NSStringFromClass([editor class]) isEqualToString:@"ElisaAppKitSensitiveFieldEditor"],
                                          "sensitive field did not receive the privacy-aware editor");
            NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:@"Copy"
                                                              action:@selector(copy:)
                                                       keyEquivalent:@""];
            NSMenuItem *cutItem = [[NSMenuItem alloc] initWithTitle:@"Cut"
                                                             action:@selector(cut:)
                                                      keyEquivalent:@""];
            failures += elisa_test_expect(![editor validateUserInterfaceItem:copyItem] &&
                                              ![editor validateUserInterfaceItem:cutItem],
                                          "sensitive field editor left Copy or Cut enabled");
            NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
            [pasteboard clearContents];
            NSArray<NSPasteboardType> *types = @[NSPasteboardTypeString];
            failures += elisa_test_expect(![editor writeSelectionToPasteboard:pasteboard
                                                                          type:NSPasteboardTypeString] &&
                                              pasteboard.types.count == 0,
                                          "sensitive field wrote a single-type pasteboard selection");
            failures += elisa_test_expect(![editor writeSelectionToPasteboard:pasteboard types:types] &&
                                              pasteboard.types.count == 0,
                                          "sensitive field editor wrote selection to a pasteboard");
            [editor copy:nil];
            [editor cut:nil];
            failures += elisa_test_expect([editor.string isEqualToString:field.stringValue],
                                          "sensitive Copy/Cut changed the editable value");

            elisa_appkit_set_accessibility_sensitive(handle, 0, 0);
            failures += elisa_test_expect([editor validateUserInterfaceItem:copyItem] &&
                                              [editor validateUserInterfaceItem:cutItem],
                                          "clearing sensitivity did not re-enable Copy and Cut");
        }
        elisa_appkit_release(windowHandle);
        elisa_appkit_release(handle);

        size_t secureHandle = elisa_appkit_create_secure_text_field(initialHandle);
        if (secureHandle == 0) return 1;
        NSSecureTextField *secure = (__bridge NSSecureTextField *)(void *)secureHandle;
        elisa_appkit_set_accessibility_sensitive(secureHandle, 1, genericHandle);
        failures += elisa_test_expect([secure isKindOfClass:[NSSecureTextField class]],
                                      "sensitive secure field lost its native secure-field class");
        failures += elisa_test_expect(secure.isEditable && secure.isSelectable,
                                      "sensitive secure-field subclass lost native text editing");
        failures += elisa_test_expect(secure.accessibilityValue.length == 0 &&
                                          [secure.stringValue isEqualToString:initial],
                                      "secure field did not retain its secret while redacting AX value");
        elisa_appkit_release(secureHandle);

        size_t labelHandle = elisa_appkit_create_label(initialHandle);
        if (labelHandle == 0) return 1;
        NSTextField *label = (__bridge NSTextField *)(void *)labelHandle;
        elisa_appkit_set_accessibility_sensitive(labelHandle, 1, genericHandle);
        failures += elisa_test_expect(label.accessibilityValue.length == 0 &&
                                          [label.stringValue isEqualToString:initial],
                                      "sensitive label exposed its text as an accessibility value");
        elisa_appkit_set_accessibility_sensitive(labelHandle, 0, 0);
        failures += elisa_test_expect([label.accessibilityValue isEqualToString:initial],
                                      "clearing label sensitivity did not restore its value");
        elisa_appkit_release(labelHandle);

        size_t buttonHandle = elisa_appkit_create_push_button(0, initialHandle);
        if (buttonHandle == 0) return 1;
        NSButton *button = (__bridge NSButton *)(void *)buttonHandle;
        elisa_appkit_set_button_state(buttonHandle, 1);
        elisa_appkit_set_accessibility_sensitive(buttonHandle, 1, genericHandle);
        failures += elisa_test_expect(((NSString *)button.accessibilityValue).length == 0 && button.state == 1,
                                      "sensitive button leaked its value or lost its selected state");
        elisa_appkit_release(buttonHandle);

        size_t sliderHandle = elisa_appkit_create_slider(0.0f, 1.0f, 0.4f);
        if (sliderHandle == 0) return 1;
        NSSlider *slider = (__bridge NSSlider *)(void *)sliderHandle;
        elisa_appkit_set_accessibility_sensitive(sliderHandle, 1, genericHandle);
        failures += elisa_test_expect(((NSString *)slider.accessibilityValue).length == 0 &&
                                          slider.doubleValue > 0.39 && slider.doubleValue < 0.41,
                                      "sensitive slider leaked its value or changed the model value");
        elisa_appkit_release(sliderHandle);

        size_t progressHandle = elisa_appkit_create_progress_bar(0, 0);
        if (progressHandle == 0) return 1;
        NSProgressIndicator *progress = (__bridge NSProgressIndicator *)(void *)progressHandle;
        elisa_appkit_set_progress_state(progressHandle, 0.0f, 1.0f, 0.6f);
        elisa_appkit_set_accessibility_sensitive(progressHandle, 1, genericHandle);
        failures += elisa_test_expect(((NSString *)progress.accessibilityValue).length == 0 &&
                                          progress.doubleValue > 0.59 && progress.doubleValue < 0.61,
                                      "sensitive progress indicator leaked or changed its value");
        elisa_appkit_release(progressHandle);

        if (failures == 0) {
            puts("appkit-controls-privacy: all checks passed");
            return 0;
        }
        return 1;
    }
}
