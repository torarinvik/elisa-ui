#include "android_utf8_utf16.h"

#include <stdio.h>
#include <string.h>

#define CHECK(condition, description) \
    do { \
        if (!(condition)) { \
            fprintf(stderr, "FAIL: %s (line %d)\n", description, __LINE__); \
            return 1; \
        } \
    } while (0)

int main(void) {
    const uint8_t text[] = {
        'A', 0xc3, 0xa9, 0xe5, 0x90, 0x8d, 0xf0, 0x9f, 0x91, 0x8b
    };
    const uint16_t expected_units[] = {0x0041, 0x00e9, 0x540d, 0xd83d, 0xdc4b};
    uint16_t units[16] = {0};
    size_t unit_count = elisa_android_utf8_to_utf16(text, sizeof(text), units, 16);
    CHECK(unit_count == sizeof(expected_units) / sizeof(expected_units[0]), "UTF-8 scalar count");
    CHECK(memcmp(units, expected_units, sizeof(expected_units)) == 0, "BMP and supplementary UTF-16");

    uint8_t roundtrip[32] = {0};
    size_t byte_count = elisa_android_utf16_to_utf8(units, unit_count, roundtrip, sizeof(roundtrip));
    CHECK(byte_count == sizeof(text), "UTF-16 round-trip byte count");
    CHECK(memcmp(roundtrip, text, sizeof(text)) == 0, "standard UTF-8 round trip");

    const uint8_t nul_text[] = {'A', 0, 'B'};
    unit_count = elisa_android_utf8_to_utf16(nul_text, sizeof(nul_text), units, 16);
    CHECK(unit_count == 3 && units[0] == 'A' && units[1] == 0 && units[2] == 'B', "embedded NUL to UTF-16");
    byte_count = elisa_android_utf16_to_utf8(units, unit_count, roundtrip, sizeof(roundtrip));
    CHECK(byte_count == sizeof(nul_text) && memcmp(roundtrip, nul_text, sizeof(nul_text)) == 0,
          "embedded NUL round trip with explicit lengths");

    const uint16_t lone_surrogates[] = {0xd800, 'x', 0xdc00};
    const uint8_t replacement_text[] = {0xef, 0xbf, 0xbd, 'x', 0xef, 0xbf, 0xbd};
    byte_count = elisa_android_utf16_to_utf8(lone_surrogates, 3, roundtrip, sizeof(roundtrip));
    CHECK(byte_count == sizeof(replacement_text) &&
          memcmp(roundtrip, replacement_text, sizeof(replacement_text)) == 0,
          "lone UTF-16 surrogates become U+FFFD");

    const uint8_t invalid_utf8[] = {0xc0, 0xaf, 0xed, 0xa0, 0x80, 0xf4, 0x90, 0x80, 0x80};
    unit_count = elisa_android_utf8_to_utf16(invalid_utf8, sizeof(invalid_utf8), units, 16);
    CHECK(unit_count == sizeof(invalid_utf8), "each malformed UTF-8 byte is bounded and replaced");
    for (size_t index = 0; index < unit_count; index += 1) {
        CHECK(units[index] == 0xfffd, "malformed UTF-8 replacement scalar");
    }

    const uint8_t emoji[] = {0xf0, 0x9f, 0x91, 0x8b};
    CHECK(elisa_android_utf8_to_utf16(emoji, sizeof(emoji), units, 1) == 0,
          "UTF-8 to UTF-16 capacity never splits a surrogate pair");
    CHECK(elisa_android_utf16_to_utf8(expected_units + 3, 2, roundtrip, 3) == 0,
          "UTF-16 to UTF-8 capacity never splits a scalar");
    CHECK(elisa_android_utf16_to_utf8(expected_units + 3, 2, roundtrip, 4) == 4 &&
          memcmp(roundtrip, emoji, sizeof(emoji)) == 0, "supplementary scalar at exact capacity");

    puts("android UTF-8/UTF-16 codec: all checks passed");
    return 0;
}
