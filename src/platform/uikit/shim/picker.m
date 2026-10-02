// Fragment of uikit_shim.m: native picker presentation and bounded selections.
// UIKit owns the dialogs and temporary URLs; Elisa receives only typed facts
// and opaque IDs, then reads copied bytes through a bounded bridge.

#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

enum {
    ElisaUiKitPickerPhotos = 2,
    ElisaUiKitPickerFiles = 5,
    ElisaUiKitPickerSelected = 2,
    ElisaUiKitPickerCancelled = 3,
    ElisaUiKitPickerFailed = 4,
    ElisaUiKitPickerUnavailable = 5,
    ElisaUiKitSelectionUnknown = 0,
    ElisaUiKitSelectionImage = 1,
    ElisaUiKitSelectionAudio = 2,
    ElisaUiKitSelectionVideo = 3,
    ElisaUiKitSelectionText = 4,
    ElisaUiKitSelectionApplication = 5,
    ElisaUiKitSelectionOther = 6,
};

@interface ElisaUiKitSelectionStore : NSObject
+ (uint64_t)remember:(NSData *)data;
+ (int)read:(uint64_t)identifier offset:(uint64_t)offset buffer:(uint8_t *)buffer capacity:(int)capacity;
+ (int)release:(uint64_t)identifier;
@end

static NSMutableDictionary<NSNumber *, NSData *> *elisa_uikit_selections;
static uint64_t elisa_uikit_next_selection_id = 1;
static NSUInteger elisa_uikit_selection_bytes = 0;
static const NSUInteger ElisaUiKitMaxSelectionBytes = 16u * 1024u * 1024u;
static const NSUInteger ElisaUiKitMaxStoredBytes = 32u * 1024u * 1024u;
static const NSUInteger ElisaUiKitMaxSelections = 16;

@implementation ElisaUiKitSelectionStore

+ (void)initialize {
    if (self == [ElisaUiKitSelectionStore class]) {
        elisa_uikit_selections = [[NSMutableDictionary alloc] init];
    }
}

+ (uint64_t)remember:(NSData *)data {
    if (data == nil || data.length > ElisaUiKitMaxSelectionBytes) return 0;
    @synchronized (self) {
        if (elisa_uikit_selections.count >= ElisaUiKitMaxSelections ||
            data.length > ElisaUiKitMaxStoredBytes - elisa_uikit_selection_bytes ||
            elisa_uikit_next_selection_id == 0) return 0;
        uint64_t identifier = elisa_uikit_next_selection_id++;
        elisa_uikit_selections[@(identifier)] = [data copy];
        elisa_uikit_selection_bytes += data.length;
        return identifier;
    }
}

+ (int)read:(uint64_t)identifier offset:(uint64_t)offset buffer:(uint8_t *)buffer capacity:(int)capacity {
    if (identifier == 0 || offset > INT64_MAX || capacity < 0 || capacity > 65536 ||
        (capacity > 0 && buffer == NULL)) return -1;
    NSData *data = nil;
    @synchronized (self) {
        data = elisa_uikit_selections[@(identifier)];
    }
    if (data == nil || offset > data.length) return -1;
    NSUInteger start = (NSUInteger)offset;
    NSUInteger count = MIN((NSUInteger)capacity, data.length - start);
    if (count > 0) [data getBytes:buffer range:NSMakeRange(start, count)];
    return (int)count;
}

+ (int)release:(uint64_t)identifier {
    if (identifier == 0) return 0;
    @synchronized (self) {
        NSNumber *key = @(identifier);
        NSData *data = elisa_uikit_selections[key];
        if (data == nil) return 0;
        elisa_uikit_selection_bytes -= data.length;
        [elisa_uikit_selections removeObjectForKey:key];
        return 1;
    }
}

@end

static NSData *elisa_uikit_read_document(NSURL *url) {
    if (url == nil || !url.isFileURL) return nil;
    NSNumber *fileSize = nil;
    NSError *error = nil;
    if ([url getResourceValue:&fileSize forKey:NSURLFileSizeKey error:&error] &&
        fileSize.unsignedLongLongValue > ElisaUiKitMaxSelectionBytes) return nil;

    NSInputStream *stream = [NSInputStream inputStreamWithURL:url];
    if (stream == nil) return nil;
    [stream open];
    NSMutableData *result = [NSMutableData dataWithCapacity:8192];
    uint8_t chunk[8192];
    while (YES) {
        NSInteger count = [stream read:chunk maxLength:sizeof(chunk)];
        if (count < 0 || (NSUInteger)count > ElisaUiKitMaxSelectionBytes - result.length) {
            [stream close];
            return nil;
        }
        if (count == 0) break;
        [result appendBytes:chunk length:(NSUInteger)count];
    }
    [stream close];
    return [result copy];
}

static uint32_t elisa_uikit_selection_kind(NSURL *url) {
    UTType *type = [UTType typeWithFilenameExtension:url.pathExtension];
    if (type == nil) return ElisaUiKitSelectionOther;
    if ([type conformsToType:UTTypeImage]) return ElisaUiKitSelectionImage;
    if ([type conformsToType:UTTypeAudio]) return ElisaUiKitSelectionAudio;
    if ([type conformsToType:UTTypeVideo] || [type conformsToType:UTTypeMovie]) return ElisaUiKitSelectionVideo;
    if ([type conformsToType:UTTypeText]) return ElisaUiKitSelectionText;
    if ([type conformsToType:UTTypeApplication]) return ElisaUiKitSelectionApplication;
    return ElisaUiKitSelectionOther;
}

@interface ElisaUiKitPickerDelegate : NSObject <PHPickerViewControllerDelegate, UIDocumentPickerDelegate>
@property(nonatomic, assign) uint32_t slot;
@property(nonatomic, assign) uint32_t generation;
@property(nonatomic, assign) BOOL finished;
- (void)finish:(int)state selectionKind:(uint32_t)selectionKind selectionID:(uint64_t)selectionID;
@end

static __strong ElisaUiKitPickerDelegate *elisa_uikit_active_picker;

@implementation ElisaUiKitPickerDelegate

- (void)finish:(int)state selectionKind:(uint32_t)selectionKind selectionID:(uint64_t)selectionID {
    if (self.finished) {
        if (selectionID != 0) (void)[ElisaUiKitSelectionStore release:selectionID];
        return;
    }
    self.finished = YES;
    int accepted = elisa_uikit_picker_result(self.slot, self.generation, state,
                                             selectionKind, selectionID);
    if (accepted != 1 && selectionID != 0) {
        (void)[ElisaUiKitSelectionStore release:selectionID];
    }
    if (elisa_uikit_active_picker == self) elisa_uikit_active_picker = nil;
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    if (results.count != 1) {
        [picker dismissViewControllerAnimated:YES completion:^{
            [self finish:ElisaUiKitPickerCancelled selectionKind:ElisaUiKitSelectionUnknown selectionID:0];
        }];
        return;
    }
    NSItemProvider *provider = results.firstObject.itemProvider;
    if (![provider hasItemConformingToTypeIdentifier:UTTypeImage.identifier]) {
        [picker dismissViewControllerAnimated:YES completion:^{
            [self finish:ElisaUiKitPickerFailed selectionKind:ElisaUiKitSelectionUnknown selectionID:0];
        }];
        return;
    }
    [picker dismissViewControllerAnimated:YES completion:^{
        [provider loadDataRepresentationForTypeIdentifier:UTTypeImage.identifier
                                        completionHandler:^(NSData *data, NSError *error) {
            (void)error;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (data == nil || data.length == 0 || data.length > ElisaUiKitMaxSelectionBytes) {
                    [self finish:ElisaUiKitPickerFailed selectionKind:ElisaUiKitSelectionUnknown selectionID:0];
                    return;
                }
                uint64_t identifier = [ElisaUiKitSelectionStore remember:data];
                if (identifier == 0) {
                    [self finish:ElisaUiKitPickerFailed selectionKind:ElisaUiKitSelectionUnknown selectionID:0];
                    return;
                }
                [self finish:ElisaUiKitPickerSelected selectionKind:ElisaUiKitSelectionImage selectionID:identifier];
            });
        }];
    }];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [controller dismissViewControllerAnimated:YES completion:^{
        [self finish:ElisaUiKitPickerCancelled selectionKind:ElisaUiKitSelectionUnknown selectionID:0];
    }];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
 didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count != 1) {
        [controller dismissViewControllerAnimated:YES completion:^{
            [self finish:ElisaUiKitPickerFailed selectionKind:ElisaUiKitSelectionUnknown selectionID:0];
        }];
        return;
    }
    NSURL *url = urls.firstObject;
    uint32_t selectionKind = elisa_uikit_selection_kind(url);
    BOOL scoped = [url startAccessingSecurityScopedResource];
    [controller dismissViewControllerAnimated:YES completion:^{
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSData *data = elisa_uikit_read_document(url);
            if (scoped) [url stopAccessingSecurityScopedResource];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (data == nil) {
                    [self finish:ElisaUiKitPickerFailed selectionKind:ElisaUiKitSelectionUnknown selectionID:0];
                    return;
                }
                uint64_t identifier = [ElisaUiKitSelectionStore remember:data];
                if (identifier == 0) {
                    [self finish:ElisaUiKitPickerFailed selectionKind:ElisaUiKitSelectionUnknown selectionID:0];
                    return;
                }
                [self finish:ElisaUiKitPickerSelected selectionKind:selectionKind selectionID:identifier];
            });
        });
    }];
}

@end

int elisa_uikit_present_picker(int kind, uint32_t slot, uint32_t generation) {
    if (!NSThread.isMainThread || (kind != ElisaUiKitPickerPhotos && kind != ElisaUiKitPickerFiles) ||
        slot >= 64 || generation == 0 || elisa_uikit_active_picker != nil) return 0;
    ElisaUiKitAppDelegate *delegate = (ElisaUiKitAppDelegate *)UIApplication.sharedApplication.delegate;
    UIViewController *presenter = delegate.controller;
    if (presenter == nil || presenter.presentedViewController != nil) return 0;

    ElisaUiKitPickerDelegate *pickerDelegate = [[ElisaUiKitPickerDelegate alloc] init];
    pickerDelegate.slot = slot;
    pickerDelegate.generation = generation;
    elisa_uikit_active_picker = pickerDelegate;

    UIViewController *picker = nil;
    if (kind == ElisaUiKitPickerPhotos) {
        PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
        configuration.filter = PHPickerFilter.imagesFilter;
        configuration.selectionLimit = 1;
        PHPickerViewController *photos = [[PHPickerViewController alloc] initWithConfiguration:configuration];
        photos.delegate = pickerDelegate;
        picker = photos;
    } else {
        UIDocumentPickerViewController *files =
            [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
        files.delegate = pickerDelegate;
        picker = files;
    }
    if (picker == nil) {
        elisa_uikit_active_picker = nil;
        return 0;
    }
    [presenter presentViewController:picker animated:YES completion:nil];
    return 1;
}

int elisa_uikit_read_selection(uint64_t selectionID, uint64_t offset, uint8_t *buffer, int capacity) {
    return [ElisaUiKitSelectionStore read:selectionID offset:offset buffer:buffer capacity:capacity];
}

int elisa_uikit_release_selection(uint64_t selectionID) {
    return [ElisaUiKitSelectionStore release:selectionID];
}
