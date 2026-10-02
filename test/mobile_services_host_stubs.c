#include <stdint.h>
#include <stddef.h>

static int32_t uikit_request_result = 1;
static int32_t android_request_result = 1;
static int32_t uikit_request_count = 0;
static int32_t android_request_count = 0;
static int32_t android_frame_count = 0;
static int32_t uikit_last_kind = -1;
static int32_t uikit_picker_result = 1;
static int32_t uikit_picker_count = 0;
static int32_t uikit_selection_release_count = 0;
static int32_t android_last_kind = -1;
static int32_t android_picker_result = 1;
static int32_t android_picker_count = 0;
static int32_t android_selection_release_count = 0;

void elisa_test_uikit_set_request_result(int32_t value) { uikit_request_result = value; }
void elisa_test_android_set_request_result(int32_t value) { android_request_result = value; }
int32_t elisa_test_uikit_request_count(void) { return uikit_request_count; }
int32_t elisa_test_android_request_count(void) { return android_request_count; }
int32_t elisa_test_android_frame_count(void) { return android_frame_count; }
int32_t elisa_test_uikit_last_kind(void) { return uikit_last_kind; }
void elisa_test_uikit_set_picker_result(int32_t value) { uikit_picker_result = value; }
int32_t elisa_test_uikit_picker_count(void) { return uikit_picker_count; }
int32_t elisa_test_uikit_selection_release_count(void) { return uikit_selection_release_count; }
int32_t elisa_test_android_last_kind(void) { return android_last_kind; }
void elisa_test_android_set_picker_result(int32_t value) { android_picker_result = value; }
int32_t elisa_test_android_picker_count(void) { return android_picker_count; }
int32_t elisa_test_android_selection_release_count(void) { return android_selection_release_count; }

int32_t elisa_uikit_request_permission(int32_t kind, uint32_t slot, uint32_t generation) {
    (void)slot;
    (void)generation;
    uikit_last_kind = kind;
    uikit_request_count += 1;
    return uikit_request_result;
}

int32_t elisa_uikit_present_picker(int32_t kind, uint32_t slot, uint32_t generation) {
    (void)slot;
    (void)generation;
    uikit_last_kind = kind;
    uikit_picker_count += 1;
    return uikit_picker_result;
}

int32_t elisa_uikit_read_selection(uint64_t selection_id, uint64_t offset,
                                   uint8_t *buffer, int32_t capacity) {
    static const uint8_t bytes[] = {'b', 'y', 't', 'e', 's'};
    if (selection_id != 77 || offset > sizeof(bytes) || capacity < 0 ||
        (capacity > 0 && buffer == NULL)) return -1;
    uint64_t remaining = sizeof(bytes) - offset;
    int32_t count = remaining < (uint64_t)capacity ? (int32_t)remaining : capacity;
    for (int32_t index = 0; index < count; ++index) buffer[index] = bytes[offset + (uint64_t)index];
    return count;
}

int32_t elisa_uikit_release_selection(uint64_t selection_id) {
    if (selection_id != 77) return 0;
    uikit_selection_release_count += 1;
    return 1;
}

int32_t elisa_android_request_permission(int32_t kind, uint32_t slot, uint32_t generation) {
    (void)slot;
    (void)generation;
    android_last_kind = kind;
    android_request_count += 1;
    return android_request_result;
}

int32_t elisa_android_present_picker(int32_t kind, uint32_t slot, uint32_t generation) {
    (void)slot;
    (void)generation;
    android_last_kind = kind;
    android_picker_count += 1;
    return android_picker_result;
}

int32_t elisa_android_read_selection(uint64_t selection_id, uint64_t offset,
                                     uint8_t *buffer, int32_t capacity) {
    static const uint8_t bytes[] = {'b', 'y', 't', 'e', 's'};
    if (selection_id != 77 || offset > sizeof(bytes) || capacity < 0 ||
        (capacity > 0 && buffer == NULL)) return -1;
    uint64_t remaining = sizeof(bytes) - offset;
    int32_t count = remaining < (uint64_t)capacity ? (int32_t)remaining : capacity;
    for (int32_t index = 0; index < count; ++index) buffer[index] = bytes[offset + (uint64_t)index];
    return count;
}

int32_t elisa_android_release_selection(uint64_t selection_id) {
    if (selection_id != 77) return 0;
    android_selection_release_count += 1;
    return 1;
}

void elisa_android_request_frame(void) { android_frame_count += 1; }
