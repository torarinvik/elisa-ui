#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static uint32_t command_calls;
static uint32_t semantic_calls;
static uint32_t command_count;
static int32_t callback_failures;

static uint32_t read_u32(const uint8_t *bytes) {
    return (uint32_t)bytes[0]
         | ((uint32_t)bytes[1] << 8)
         | ((uint32_t)bytes[2] << 16)
         | ((uint32_t)bytes[3] << 24);
}

#if defined(__APPLE__)
#define HOST_WIT_SYMBOL(name) __asm__("_" name)
#else
#define HOST_WIT_SYMBOL(name) __asm__(name)
#endif

void host_present_commands(uint32_t width, uint32_t height, void *commands, uint32_t count)
    HOST_WIT_SYMBOL("present-commands");
void host_present_semantics(uint64_t sequence, bool complete, const char *snapshot, uint32_t count)
    HOST_WIT_SYMBOL("present-semantics");
void host_log_diagnostic(uint32_t severity, uint32_t code, const char *source, uint32_t source_length,
    uint32_t line, uint32_t column, const char *message, uint32_t message_length, bool redacted)
    HOST_WIT_SYMBOL("log-diagnostic");

void host_present_commands(uint32_t width, uint32_t height, void *commands, uint32_t count) {
    command_calls += 1;
    command_count = count;
    const uint8_t *bytes = (const uint8_t *)commands;
    if (width != 640 || height != 480 || count != 3 || commands == NULL)
        callback_failures += 1;
    if (bytes != NULL && (read_u32(bytes) != 0
        || read_u32(bytes + 32) != 1
        || read_u32(bytes + 64) != 5
        || read_u32(bytes + 88) != 2))
        callback_failures += 1;
}

void host_present_semantics(uint64_t sequence, bool complete, const char *snapshot, uint32_t count) {
    semantic_calls += 1;
    uint32_t expected_nodes = semantic_calls == 1 ? 1 : 256;
    uint32_t expected_text_bytes = semantic_calls == 1 ? 9 : 3072;
    uint32_t expected_length = 8 + expected_nodes * 120 + expected_text_bytes;
    const uint8_t *bytes = (const uint8_t *)snapshot;
    if (sequence != semantic_calls || !complete || count != expected_length || snapshot == NULL)
        callback_failures += 1;
    if (bytes != NULL && (read_u32(bytes) != 1 || read_u32(bytes + 4) != expected_nodes))
        callback_failures += 1;
    if (semantic_calls == 1 && bytes != NULL) {
        if (read_u32(bytes + 104) != 128 || read_u32(bytes + 108) != 2
            || read_u32(bytes + 112) != 130 || read_u32(bytes + 116) != 3
            || read_u32(bytes + 120) != 133 || read_u32(bytes + 124) != 4
            || memcmp(bytes + 128, "OKTipDone", 9) != 0)
            callback_failures += 1;
    }
    if (semantic_calls == 2 && bytes != NULL) {
        const uint32_t text_start = 8 + 256 * 120;
        const uint32_t last_record = 8 + 255 * 120;
        if (read_u32(bytes + 104) != text_start || read_u32(bytes + 108) != 4
            || read_u32(bytes + 112) != text_start + 4 || read_u32(bytes + 116) != 4
            || read_u32(bytes + 120) != text_start + 8 || read_u32(bytes + 124) != 4
            || read_u32(bytes + last_record + 96) != count - 12
            || read_u32(bytes + last_record + 104) != count - 8
            || read_u32(bytes + last_record + 112) != count - 4
            || memcmp(bytes + text_start, "NodeHelpText", 12) != 0
            || memcmp(bytes + count - 4, "Text", 4) != 0)
            callback_failures += 1;
    }
}

void host_log_diagnostic(uint32_t severity, uint32_t code, const char *source, uint32_t source_length,
    uint32_t line, uint32_t column, const char *message, uint32_t message_length, bool redacted) {
    (void)severity;
    (void)code;
    (void)source;
    (void)source_length;
    (void)line;
    (void)column;
    (void)message;
    (void)message_length;
    (void)redacted;
}

int32_t wasmbrowser_transfer_assertions(void) {
    const uint32_t command_stride = 32;
    const uint32_t command_bytes = command_count * command_stride;
    const uint32_t small_semantic_bytes = 8 + 120 + 9;
    const uint32_t max_semantic_bytes = 8 + 256 * 120 + 3072;
    if (command_calls != 2 || semantic_calls != 2)
        callback_failures += 1;
    printf("WasmBrowser host-visible frame payload: commands=%u bytes (%u x %u), semantics=%u / %u bytes (small / maximum)\n",
        command_bytes, command_count, command_stride, small_semantic_bytes, max_semantic_bytes);
    return callback_failures;
}
