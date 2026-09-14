// Platform text APIs use UTF-16 while Elisa's text views use standard UTF-8.
// JNI's *UTF* byte helpers are modified UTF-8, so this small shared codec is
// deliberately independent of host APIs and can be tested on the host.
#ifndef ELISA_UTF8_UTF16_H
#define ELISA_UTF8_UTF16_H

#include <stddef.h>
#include <stdint.h>

// Decode one standard UTF-8 scalar. Ill-formed input consumes one byte and
// becomes U+FFFD. This makes the malformed-input policy deterministic without
// ever passing invalid UTF-8 into the retained text layer.
static inline size_t elisa_decode_utf8(const uint8_t *bytes, size_t length,
                                       uint32_t *scalar) {
    if (bytes == NULL || length == 0 || scalar == NULL) return 0;

    uint8_t first = bytes[0];
    if (first <= 0x7f) {
        *scalar = first;
        return 1;
    }

    if (first >= 0xc2 && first <= 0xdf && length >= 2 &&
        (bytes[1] & 0xc0) == 0x80) {
        *scalar = ((uint32_t)(first & 0x1f) << 6) | (uint32_t)(bytes[1] & 0x3f);
        return 2;
    }

    if (first >= 0xe0 && first <= 0xef && length >= 3 &&
        (bytes[1] & 0xc0) == 0x80 && (bytes[2] & 0xc0) == 0x80 &&
        !(first == 0xe0 && bytes[1] < 0xa0) &&
        !(first == 0xed && bytes[1] > 0x9f)) {
        *scalar = ((uint32_t)(first & 0x0f) << 12) |
                  ((uint32_t)(bytes[1] & 0x3f) << 6) |
                  (uint32_t)(bytes[2] & 0x3f);
        return 3;
    }

    if (first >= 0xf0 && first <= 0xf4 && length >= 4 &&
        (bytes[1] & 0xc0) == 0x80 && (bytes[2] & 0xc0) == 0x80 &&
        (bytes[3] & 0xc0) == 0x80 &&
        !(first == 0xf0 && bytes[1] < 0x90) &&
        !(first == 0xf4 && bytes[1] > 0x8f)) {
        *scalar = ((uint32_t)(first & 0x07) << 18) |
                  ((uint32_t)(bytes[1] & 0x3f) << 12) |
                  ((uint32_t)(bytes[2] & 0x3f) << 6) |
                  (uint32_t)(bytes[3] & 0x3f);
        return 4;
    }

    *scalar = 0xfffd;
    return 1;
}

// Convert a counted standard UTF-8 view to UTF-16 code units. The output is
// always a scalar-aligned prefix; no terminator is reserved or written, so U+0000
// remains ordinary counted text. The capacity bounds both output and work.
static inline size_t elisa_utf8_to_utf16(const uint8_t *bytes, size_t length,
                                          uint16_t *units, size_t capacity) {
    if (bytes == NULL || units == NULL || capacity == 0) return 0;

    size_t input = 0;
    size_t output = 0;
    while (input < length && output < capacity) {
        uint32_t scalar = 0;
        size_t consumed = elisa_decode_utf8(bytes + input, length - input, &scalar);
        if (consumed == 0) break;
        size_t needed = scalar > 0xffff ? 2 : 1;
        if (needed > capacity - output) break;

        if (needed == 1) {
            units[output++] = (uint16_t)scalar;
        } else {
            scalar -= 0x10000;
            units[output++] = (uint16_t)(0xd800 | (scalar >> 10));
            units[output++] = (uint16_t)(0xdc00 | (scalar & 0x3ff));
        }
        input += consumed;
    }
    return output;
}

static inline size_t elisa_encode_utf8(uint32_t scalar, uint8_t bytes[4]) {
    if (scalar <= 0x7f) {
        bytes[0] = (uint8_t)scalar;
        return 1;
    }
    if (scalar <= 0x7ff) {
        bytes[0] = (uint8_t)(0xc0 | (scalar >> 6));
        bytes[1] = (uint8_t)(0x80 | (scalar & 0x3f));
        return 2;
    }
    if (scalar <= 0xffff) {
        bytes[0] = (uint8_t)(0xe0 | (scalar >> 12));
        bytes[1] = (uint8_t)(0x80 | ((scalar >> 6) & 0x3f));
        bytes[2] = (uint8_t)(0x80 | (scalar & 0x3f));
        return 3;
    }
    bytes[0] = (uint8_t)(0xf0 | (scalar >> 18));
    bytes[1] = (uint8_t)(0x80 | ((scalar >> 12) & 0x3f));
    bytes[2] = (uint8_t)(0x80 | ((scalar >> 6) & 0x3f));
    bytes[3] = (uint8_t)(0x80 | (scalar & 0x3f));
    return 4;
}

// Convert counted UTF-16 to standard UTF-8. Valid surrogate pairs become one
// scalar; lone surrogates become U+FFFD. Never emit a partial UTF-8 sequence.
static inline size_t elisa_utf16_to_utf8(const uint16_t *units, size_t length,
                                          uint8_t *bytes, size_t capacity) {
    if (units == NULL || bytes == NULL || capacity == 0) return 0;

    size_t input = 0;
    size_t output = 0;
    while (input < length) {
        uint32_t scalar = units[input];
        size_t consumed = 1;
        if (scalar >= 0xd800 && scalar <= 0xdbff) {
            if (input + 1 < length && units[input + 1] >= 0xdc00 && units[input + 1] <= 0xdfff) {
                scalar = 0x10000 + ((scalar - 0xd800) << 10) + (units[input + 1] - 0xdc00);
                consumed = 2;
            } else {
                scalar = 0xfffd;
            }
        } else if (scalar >= 0xdc00 && scalar <= 0xdfff) {
            scalar = 0xfffd;
        }

        uint8_t encoded[4];
        size_t produced = elisa_encode_utf8(scalar, encoded);
        if (produced > capacity - output) break;
        for (size_t index = 0; index < produced; index += 1) bytes[output + index] = encoded[index];
        output += produced;
        input += consumed;
    }
    return output;
}

#endif
