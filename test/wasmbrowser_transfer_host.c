#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static uint32_t command_calls;
static uint32_t semantic_calls;
static uint32_t command_count;
static int32_t callback_failures;
static const void *command_buffer_identity;
static const char *semantic_buffer_identity;

static uint32_t read_u32(const uint8_t *bytes) {
    return (uint32_t)bytes[0]
         | ((uint32_t)bytes[1] << 8)
         | ((uint32_t)bytes[2] << 16)
         | ((uint32_t)bytes[3] << 24);
}

static float read_f32(const uint8_t *bytes) {
    uint32_t bits = read_u32(bytes);
    float value;
    memcpy(&value, &bits, sizeof(value));
    return value;
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
    if (command_calls == 1)
        command_buffer_identity = commands;
    else if (commands != command_buffer_identity)
        callback_failures += 1;
    if (width != 640 || height != 480 || count != 7 || commands == NULL)
        callback_failures += 1;
    if (bytes != NULL) {
        if (bytes[0] != 0 || bytes[4] != 1 || bytes[5] != 2 || bytes[6] != 3 || bytes[7] != 255
            || bytes[32] != 1 || read_f32(bytes + 36) != 4.0f || read_f32(bytes + 40) != 5.0f
            || read_f32(bytes + 44) != 60.0f || read_f32(bytes + 48) != 20.0f
            || bytes[52] != 8 || bytes[53] != 9 || bytes[54] != 10 || bytes[55] != 255
            || bytes[64] != 2 || read_f32(bytes + 68) != 31.0f || read_f32(bytes + 72) != 32.0f
            || read_f32(bytes + 76) != 33.0f || bytes[80] != 21 || bytes[81] != 22
            || bytes[82] != 23 || bytes[83] != 24
            || bytes[96] != 3 || read_f32(bytes + 100) != 40.0f || read_f32(bytes + 104) != 41.0f
            || read_f32(bytes + 108) != 42.0f || read_f32(bytes + 112) != 43.0f
            || read_f32(bytes + 116) != 44.0f || read_f32(bytes + 120) != 45.0f
            || bytes[124] != 31 || bytes[125] != 32 || bytes[126] != 33 || bytes[127] != 34
            || bytes[128] != 4 || read_f32(bytes + 132) != 50.0f || read_f32(bytes + 136) != 51.0f
            || read_f32(bytes + 140) != 52.0f || read_f32(bytes + 144) != 53.0f
            || bytes[148] != 41 || bytes[149] != 42 || bytes[150] != 43 || bytes[151] != 44
            || read_f32(bytes + 152) != 2.5f
            || bytes[160] != 5 || read_f32(bytes + 164) != 6.0f || read_f32(bytes + 168) != 7.0f
            || read_f32(bytes + 172) != 16.0f || bytes[176] != 11 || bytes[177] != 12
            || bytes[178] != 13 || bytes[179] != 255 || read_u32(bytes + 180) == 0
            || read_u32(bytes + 184) != 2
            || bytes[192] != 6 || read_f32(bytes + 196) != 20.0f || read_f32(bytes + 200) != 21.0f
            || read_f32(bytes + 204) != 22.0f || read_f32(bytes + 208) != 23.0f
            || read_u32(bytes + 212) != 3 || read_u32(bytes + 216) != 7
            || bytes[220] != 128 || bytes[221] != 1
            || bytes[222] != (command_calls == 1 ? 1 : 3) || bytes[223] != 0)
            callback_failures += 1;
    }
}

void host_present_semantics(uint64_t sequence, bool complete, const char *snapshot, uint32_t count) {
    semantic_calls += 1;
    if (semantic_calls == 1)
        semantic_buffer_identity = snapshot;
    else if (snapshot != semantic_buffer_identity)
        callback_failures += 1;
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
    printf("WasmBrowser host-visible frame payload: commands=%u bytes (%u x %u; tags 0-6 checked), semantics=%u / %u bytes (small / maximum); guest buffer pointers reused\n",
        command_bytes, command_count, command_stride, small_semantic_bytes, max_semantic_bytes);
    return callback_failures;
}
