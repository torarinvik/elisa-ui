// Fragment of uikit_shim.m: UITextInput.
//
// UIKit expresses text in opaque UITextPosition and UITextRange objects. Here
// they are UTF-16 offsets into the focused field and nothing more, so these
// two classes are thin wrappers and every question that needs the text itself
// -- how long the document is, whether an offset exists, what a range covers,
// where a caret sits, which offset a touch lands on -- is asked of Elisa.
//
// This is what makes composition work: a marked range from a Japanese
// keyboard, from dictation or from autocorrect reaches the retained model
// through setMarkedText:/unmarkText.

@interface ElisaUiKitTextPosition : UITextPosition
@property(nonatomic, assign) size_t offset;
+ (instancetype)withOffset:(size_t)offset;
@end

@implementation ElisaUiKitTextPosition
+ (instancetype)withOffset:(size_t)offset {
    if (offset == elisa_uikit_not_found) return nil;
    ElisaUiKitTextPosition *position = [[ElisaUiKitTextPosition alloc] init];
    position.offset = offset;
    return position;
}
@end

@interface ElisaUiKitTextRange : UITextRange
@property(nonatomic, assign) size_t location;
@property(nonatomic, assign) size_t length;
+ (instancetype)withLocation:(size_t)location length:(size_t)length;
@end

@implementation ElisaUiKitTextRange
+ (instancetype)withLocation:(size_t)location length:(size_t)length {
    if (location == elisa_uikit_not_found) return nil;
    ElisaUiKitTextRange *range = [[ElisaUiKitTextRange alloc] init];
    range.location = location;
    range.length = length;
    return range;
}
- (UITextPosition *)start { return [ElisaUiKitTextPosition withOffset:self.location]; }
- (UITextPosition *)end { return [ElisaUiKitTextPosition withOffset:self.location + self.length]; }
- (BOOL)isEmpty { return self.length == 0; }
@end

// UIKit can hand back a position it made earlier, after the field has changed
// under it. Reading one must not crash the text system, and an offset that no
// longer exists must not be used: Elisa validates it against the current
// document and answers with the sentinel when it is gone.
static size_t elisa_uikit_offset_of(size_t viewHandle, UITextPosition *position) {
    if (![position isKindOfClass:[ElisaUiKitTextPosition class]]) return elisa_uikit_not_found;
    return elisa_uikit_text_clamp_offset(viewHandle, ((ElisaUiKitTextPosition *)position).offset);
}

static ElisaUiKitTextRange *elisa_uikit_range_of(UITextRange *range) {
    return [range isKindOfClass:[ElisaUiKitTextRange class]] ? (ElisaUiKitTextRange *)range : nil;
}

// Conformance is declared on the category rather than the class: the protocol
// is implemented here, and the compiler checks the implementation it can see.
@interface ElisaUiKitView (TextInput) <UITextInput>
- (CGRect)elisaRectForLocation:(size_t)location length:(size_t)length;
@end

@implementation ElisaUiKitView (TextInput)

// The stock tokenizer. Word and sentence boundaries in the user's language are
// the text system's job, not this framework's, so it is not reimplemented.
- (id<UITextInputTokenizer>)tokenizer {
    if (self.elisaTokenizer == nil) {
        self.elisaTokenizer = [[UITextInputStringTokenizer alloc] initWithTextInput:self];
    }
    return self.elisaTokenizer;
}

// --- Document ----------------------------------------------------------

- (UITextPosition *)beginningOfDocument {
    return [ElisaUiKitTextPosition withOffset:0];
}

- (UITextPosition *)endOfDocument {
    return [ElisaUiKitTextPosition withOffset:elisa_uikit_text_length([self elisaHandle])];
}

- (NSString *)textInRange:(UITextRange *)range {
    ElisaUiKitTextRange *bounded = elisa_uikit_range_of(range);
    if (bounded == nil) return nil;
    size_t native = elisa_uikit_text_in_range([self elisaHandle], bounded.location, bounded.length);
    if (native == 0) return nil;
    return CFBridgingRelease((CFTypeRef)(void *)native);
}

- (void)replaceRange:(UITextRange *)range withText:(NSString *)text {
    ElisaUiKitTextRange *bounded = elisa_uikit_range_of(range);
    if (bounded == nil) return;
    elisa_uikit_text_replace_range([self elisaHandle], bounded.location, bounded.length,
                                   (size_t)(__bridge void *)text);
}

// --- Selection ---------------------------------------------------------

- (UITextRange *)selectedTextRange {
    size_t handle = [self elisaHandle];
    return [ElisaUiKitTextRange withLocation:elisa_uikit_text_selection_location(handle)
                                      length:elisa_uikit_text_selection_length(handle)];
}

- (void)setSelectedTextRange:(UITextRange *)range {
    ElisaUiKitTextRange *bounded = elisa_uikit_range_of(range);
    if (bounded == nil) return;
    (void)elisa_uikit_text_set_selection([self elisaHandle], bounded.location, bounded.length);
}

// --- Composition -------------------------------------------------------

- (UITextRange *)markedTextRange {
    size_t handle = [self elisaHandle];
    if (elisa_uikit_text_has_marked(handle) == 0) return nil;
    return [ElisaUiKitTextRange withLocation:elisa_uikit_text_marked_location(handle)
                                      length:elisa_uikit_text_marked_length(handle)];
}

- (NSDictionary<NSAttributedStringKey, id> *)markedTextStyle {
    // The framework paints its own composition underline, so it declines
    // UIKit's styling rather than describing a second appearance here.
    return nil;
}

- (void)setMarkedTextStyle:(NSDictionary<NSAttributedStringKey, id> *)style {
    (void)style;
}

- (void)setMarkedText:(NSString *)markedText selectedRange:(NSRange)selectedRange {
    elisa_uikit_text_set_marked([self elisaHandle], (size_t)(__bridge void *)markedText,
                                selectedRange.location, selectedRange.length);
}

- (void)unmarkText {
    elisa_uikit_text_unmark([self elisaHandle]);
}

// --- Position arithmetic -----------------------------------------------

- (UITextRange *)textRangeFromPosition:(UITextPosition *)from toPosition:(UITextPosition *)to {
    size_t start = elisa_uikit_offset_of([self elisaHandle], from);
    size_t end = elisa_uikit_offset_of([self elisaHandle], to);
    if (start == elisa_uikit_not_found || end == elisa_uikit_not_found) return nil;
    size_t low = start < end ? start : end;
    size_t high = start < end ? end : start;
    return [ElisaUiKitTextRange withLocation:low length:high - low];
}

- (UITextPosition *)positionFromPosition:(UITextPosition *)position offset:(NSInteger)offset {
    return [ElisaUiKitTextPosition
        withOffset:elisa_uikit_text_offset_position([self elisaHandle],
                                                    elisa_uikit_offset_of([self elisaHandle], position),
                                                    (int64_t)offset)];
}

- (UITextPosition *)positionFromPosition:(UITextPosition *)position
                             inDirection:(UITextLayoutDirection)direction
                                  offset:(NSInteger)offset {
    // The field is one line, so up/down have no vertical target and left/right
    // are the storage order. A layout direction the framework cannot honour
    // yields no position rather than a silently wrong one.
    if (direction == UITextLayoutDirectionUp || direction == UITextLayoutDirectionDown) return nil;
    NSInteger signedOffset = direction == UITextLayoutDirectionLeft ? -offset : offset;
    return [self positionFromPosition:position offset:signedOffset];
}

- (NSComparisonResult)comparePosition:(UITextPosition *)from toPosition:(UITextPosition *)to {
    size_t left = elisa_uikit_offset_of([self elisaHandle], from);
    size_t right = elisa_uikit_offset_of([self elisaHandle], to);
    if (left == right) return NSOrderedSame;
    return left < right ? NSOrderedAscending : NSOrderedDescending;
}

- (NSInteger)offsetFromPosition:(UITextPosition *)from toPosition:(UITextPosition *)to {
    size_t left = elisa_uikit_offset_of([self elisaHandle], from);
    size_t right = elisa_uikit_offset_of([self elisaHandle], to);
    if (left == elisa_uikit_not_found || right == elisa_uikit_not_found) return 0;
    return (NSInteger)right - (NSInteger)left;
}

- (UITextPosition *)positionWithinRange:(UITextRange *)range
                    farthestInDirection:(UITextLayoutDirection)direction {
    ElisaUiKitTextRange *bounded = elisa_uikit_range_of(range);
    if (bounded == nil) return nil;
    BOOL towardsStart = direction == UITextLayoutDirectionLeft || direction == UITextLayoutDirectionUp;
    return [ElisaUiKitTextPosition withOffset:towardsStart ? bounded.location
                                                          : bounded.location + bounded.length];
}

- (UITextRange *)characterRangeByExtendingPosition:(UITextPosition *)position
                                       inDirection:(UITextLayoutDirection)direction {
    size_t offset = elisa_uikit_offset_of([self elisaHandle], position);
    if (offset == elisa_uikit_not_found) return nil;
    BOOL towardsStart = direction == UITextLayoutDirectionLeft || direction == UITextLayoutDirectionUp;
    size_t other = elisa_uikit_text_offset_position([self elisaHandle], offset, towardsStart ? -1 : 1);
    if (other == elisa_uikit_not_found) return nil;
    size_t low = other < offset ? other : offset;
    size_t high = other < offset ? offset : other;
    return [ElisaUiKitTextRange withLocation:low length:high - low];
}

// --- Writing direction -------------------------------------------------

- (NSWritingDirection)baseWritingDirectionForPosition:(UITextPosition *)position
                                          inDirection:(UITextStorageDirection)direction {
    (void)position;
    (void)direction;
    return NSWritingDirectionNatural;
}

- (void)setBaseWritingDirection:(NSWritingDirection)direction forRange:(UITextRange *)range {
    // The retained model has one paragraph direction, resolved from the text
    // itself; UIKit cannot override it per range.
    (void)direction;
    (void)range;
}

// --- Geometry ----------------------------------------------------------

- (CGRect)elisaRectForLocation:(size_t)location length:(size_t)length {
    float x = 0.0f;
    float y = 0.0f;
    float width = 0.0f;
    float height = 0.0f;
    if (!elisa_uikit_text_rect([self elisaHandle], location, length, &x, &y, &width, &height)) {
        return CGRectZero;
    }
    return CGRectMake(x, y, width, height);
}

- (CGRect)firstRectForRange:(UITextRange *)range {
    ElisaUiKitTextRange *bounded = elisa_uikit_range_of(range);
    if (bounded == nil) return CGRectZero;
    return [self elisaRectForLocation:bounded.location length:bounded.length];
}

- (CGRect)caretRectForPosition:(UITextPosition *)position {
    size_t offset = elisa_uikit_offset_of([self elisaHandle], position);
    if (offset == elisa_uikit_not_found) return CGRectZero;
    return [self elisaRectForLocation:offset length:0];
}

- (NSArray<UITextSelectionRect *> *)selectionRectsForRange:(UITextRange *)range {
    // The field is a single line, so its selection is the one rectangle
    // firstRectForRange: already reports; UIKit uses that for the callout.
    (void)range;
    return [NSArray array];
}

- (UITextPosition *)closestPositionToPoint:(CGPoint)point {
    return [ElisaUiKitTextPosition
        withOffset:elisa_uikit_text_offset_at_x([self elisaHandle], (float)point.x)];
}

- (UITextPosition *)closestPositionToPoint:(CGPoint)point withinRange:(UITextRange *)range {
    ElisaUiKitTextRange *bounded = elisa_uikit_range_of(range);
    size_t offset = elisa_uikit_text_offset_at_x([self elisaHandle], (float)point.x);
    if (bounded == nil || offset == elisa_uikit_not_found) {
        return [ElisaUiKitTextPosition withOffset:offset];
    }
    if (offset < bounded.location) offset = bounded.location;
    if (offset > bounded.location + bounded.length) offset = bounded.location + bounded.length;
    return [ElisaUiKitTextPosition withOffset:offset];
}

- (UITextRange *)characterRangeAtPoint:(CGPoint)point {
    size_t offset = elisa_uikit_text_offset_at_x([self elisaHandle], (float)point.x);
    if (offset == elisa_uikit_not_found) return nil;
    size_t next = elisa_uikit_text_offset_position([self elisaHandle], offset, 1);
    if (next == elisa_uikit_not_found) return [ElisaUiKitTextRange withLocation:offset length:0];
    return [ElisaUiKitTextRange withLocation:offset length:next - offset];
}

@end
