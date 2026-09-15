// Shared internals of the Elisa Skia shim.
//
// The bridge is one narrow C ABI but two translation units -- the canvas
// primitives and the text ones -- and everything both halves need lives here
// rather than being written twice, which is how the two halves of a shim
// drift apart.
//
// Everything is `inline` in a NAMED namespace rather than `static` in an
// anonymous one. An anonymous namespace in a header gives each translation
// unit its own copy of every helper, and the ones a unit does not happen to
// call become unused-function errors under -Werror; `inline` variables also
// keep the text-quality and bold-face state one object rather than two.
#ifndef ELISA_SKIA_SHIM_COMMON_H_
#define ELISA_SKIA_SHIM_COMMON_H_

#include <cstddef>
#include <cstdint>
#include <cmath>

#include "../../../include/elisa_skia.h"
#include "include/core/SkCanvas.h"
#include "include/core/SkColor.h"
#include "include/core/SkFont.h"
#include "include/core/SkFontMetrics.h"
#include "include/core/SkImage.h"
#include "include/core/SkPaint.h"
#include "include/core/SkPath.h"
#include "include/core/SkPathBuilder.h"
#include "include/core/SkRect.h"
#include "include/core/SkRRect.h"
#include "include/core/SkSamplingOptions.h"
#include "include/core/SkShader.h"
#include "include/core/SkTypeface.h"
#include "include/core/SkFontMgr.h"
#include <unordered_map>
#include <vector>
#include "include/effects/SkImageFilters.h"
#include "include/core/SkMaskFilter.h"
#include "include/core/SkBlurTypes.h"
#include "include/effects/SkGradient.h"

namespace elisa_skia_shim {

inline SkCanvas *canvas(std::size_t handle) {
    return reinterpret_cast<SkCanvas *>(handle);
}

inline bool finite(float value) {
    return std::isfinite(value);
}

constexpr float max_geometry_extent = 16777216.0f;

inline bool bounded_coordinate(float value) {
    return finite(value) && value >= -max_geometry_extent && value <= max_geometry_extent;
}

inline bool bounded_extent(float value) {
    return finite(value) && value > 0.0f && value <= max_geometry_extent;
}

inline bool bounded_nonnegative_extent(float value) {
    return finite(value) && value >= 0.0f && value <= max_geometry_extent;
}

inline bool bounded_far_edge(float origin, float extent) {
    const float edge = origin + extent;
    return finite(edge) && edge <= max_geometry_extent;
}

inline bool valid_rect(float x, float y, float width, float height) {
    return bounded_coordinate(x) && bounded_coordinate(y) && bounded_extent(width) && bounded_extent(height) &&
        bounded_far_edge(x, width) && bounded_far_edge(y, height);
}

// Retained clips may intentionally be empty after Elisa intersects nested
// viewports. Keep that semantic distinction at the primitive boundary: a
// zero-sized clip is a valid Skia operation that suppresses subsequent draws,
// while negative or non-finite geometry remains malformed and is rejected.
inline bool valid_clip_rect(float x, float y, float width, float height) {
    return bounded_coordinate(x) && bounded_coordinate(y) && bounded_nonnegative_extent(width) &&
        bounded_nonnegative_extent(height) && bounded_far_edge(x, width) && bounded_far_edge(y, height);
}

inline bool valid_source_rect(float x, float y, float width, float height) {
    return x >= 0.0f && y >= 0.0f && valid_rect(x, y, width, height);
}

inline bool valid_circle(float x, float y, float radius) {
    return bounded_coordinate(x) && bounded_coordinate(y) && bounded_extent(radius) &&
        finite(x - radius) && finite(x + radius) && finite(y - radius) && finite(y + radius) &&
        x - radius >= -max_geometry_extent && x + radius <= max_geometry_extent &&
        y - radius >= -max_geometry_extent && y + radius <= max_geometry_extent;
}

inline bool valid_stroked_circle(float x, float y, float radius, float stroke_width) {
    return valid_circle(x, y, radius) && bounded_extent(stroke_width) &&
        valid_circle(x, y, radius + stroke_width * 0.5f);
}

inline bool valid_scale(float x, float y) {
    return bounded_extent(x) && bounded_extent(y);
}

inline SkColor color(std::uint8_t red, std::uint8_t green, std::uint8_t blue, std::uint8_t alpha) {
    return SkColorSetARGB(alpha, red, green, blue);
}

inline SkPaint fill_paint(std::uint8_t red, std::uint8_t green, std::uint8_t blue, std::uint8_t alpha) {
    SkPaint paint;
    paint.setAntiAlias(true);
    paint.setStyle(SkPaint::kFill_Style);
    paint.setColor(color(red, green, blue, alpha));
    return paint;
}

inline SkPaint stroke_paint(std::uint8_t red, std::uint8_t green, std::uint8_t blue, std::uint8_t alpha,
                     float width) {
    SkPaint paint = fill_paint(red, green, blue, alpha);
    paint.setStyle(SkPaint::kStroke_Style);
    paint.setStrokeWidth(width);
    return paint;
}

// Text quality is chosen by Elisa and applied here. Both knobs change how
// glyphs land on the pixel grid rather than what is drawn, so they are one
// process-wide setting instead of an argument on every draw call.
inline int elisa_skia_text_subpixel = 0;
inline int elisa_skia_text_hinting = 0;
// The bold face a host has lent the renderer, or zero. Borrowed for as long as
// the host says so, exactly like the regular face handed to each draw call.
inline std::size_t elisa_skia_bold_typeface = 0;
// A font manager the host has lent, or zero. It is the ONLY way a glyph the
// lent face lacks gets drawn as anything but a box: the shim asks it for a
// face that has the code point, per code point, and remembers the answer.
inline std::size_t elisa_skia_font_manager = 0;
// Extra advance after every scalar but the last, set per run by the painter
// and put back to zero after. Zero draws exactly as before.
inline float elisa_skia_text_tracking = 0.0f;
// A fallback face is selected from both the missing scalar and the requested
// style. Caching only by scalar makes a regular lookup poison a later bold
// lookup when both runs share the same font manager.
struct FallbackKey {
    std::uint32_t code;
    std::int32_t weight;
    std::int32_t width;
    std::int32_t slant;

    bool operator==(const FallbackKey &other) const {
        return code == other.code && weight == other.weight && width == other.width &&
            slant == other.slant;
    }
};

struct FallbackKeyHash {
    std::size_t operator()(const FallbackKey &key) const {
        std::size_t hash = static_cast<std::size_t>(key.code);
        hash ^= static_cast<std::size_t>(key.weight) + static_cast<std::size_t>(0x9e3779b9u) +
            (hash << 6) + (hash >> 2);
        hash ^= static_cast<std::size_t>(key.width) + static_cast<std::size_t>(0x9e3779b9u) +
            (hash << 6) + (hash >> 2);
        hash ^= static_cast<std::size_t>(key.slant) + static_cast<std::size_t>(0x9e3779b9u) +
            (hash << 6) + (hash >> 2);
        return hash;
    }
};

inline std::unordered_map<FallbackKey, sk_sp<SkTypeface>, FallbackKeyHash> elisa_skia_fallback_cache;

// One run of text drawn with one face. A string is split into these at every
// point where the lent face has no glyph and a fallback does -- and drawn
// and measured through the SAME split, so a run measures as it draws.
struct TextRun {
    std::size_t begin;
    std::size_t end;
    sk_sp<SkTypeface> face;   // null means the lent face
};

inline std::uint32_t decode_utf8(const char *text, std::size_t length, std::size_t &index) {
    const auto byte = [&](std::size_t at) { return static_cast<unsigned char>(text[at]); };
    const unsigned char lead = byte(index);
    std::size_t extra = lead >= 0xF0 ? 3 : lead >= 0xE0 ? 2 : lead >= 0xC0 ? 1 : 0;
    if (index + extra >= length + (extra == 0 ? 1 : 0) && extra != 0) { index += 1; return 0xFFFD; }
    std::uint32_t code = extra == 0 ? lead : extra == 1 ? (lead & 0x1F) : extra == 2 ? (lead & 0x0F) : (lead & 0x07);
    for (std::size_t k = 1; k <= extra; ++k) {
        if (index + k >= length) { index += 1; return 0xFFFD; }
        code = (code << 6) | (byte(index + k) & 0x3F);
    }
    index += extra + 1;
    return code;
}

inline sk_sp<SkTypeface> fallback_face_for(std::uint32_t code, SkTypeface *lent) {
    if (elisa_skia_font_manager == 0) return nullptr;
    SkFontMgr *manager = reinterpret_cast<SkFontMgr *>(elisa_skia_font_manager);
    const SkFontStyle style = lent != nullptr ? lent->fontStyle() : SkFontStyle::Normal();
    const FallbackKey key{code, style.weight(), style.width(), static_cast<std::int32_t>(style.slant())};
    const auto cached = elisa_skia_fallback_cache.find(key);
    if (cached != elisa_skia_fallback_cache.end()) return cached->second;
    sk_sp<SkTypeface> found = manager->matchFamilyStyleCharacter(nullptr, style, nullptr, 0,
                                                                   static_cast<SkUnichar>(code));
    // Remember misses too: a code point no face has is asked about once.
    elisa_skia_fallback_cache.emplace(key, found);
    return found;
}

inline std::vector<TextRun> split_runs(SkTypeface *lent, const char *text, std::size_t length) {
    std::vector<TextRun> runs;
    std::size_t index = 0;
    while (index < length) {
        const std::size_t start = index;
        const std::uint32_t code = decode_utf8(text, length, index);
        sk_sp<SkTypeface> face = nullptr;
        // Control characters and anything the lent face already has stay on it.
        if (code >= 0x20 && lent != nullptr && lent->unicharToGlyph(static_cast<SkUnichar>(code)) == 0) {
            face = fallback_face_for(code, lent);
        }
        if (!runs.empty() && runs.back().face.get() == face.get()) {
            runs.back().end = index;
        } else {
            runs.push_back(TextRun{start, index, face});
        }
    }
    return runs;
}

// Draw a string as its runs, advancing by each run's measured width.
inline void draw_runs(SkCanvas *target, const SkFont &base, const SkPaint &paint, SkTypeface *lent,
                      const char *text, std::size_t length, float x, float y) {
    float pen = x;
    const float tracking = elisa_skia_text_tracking;
    for (const TextRun &run : split_runs(lent, text, length)) {
        SkFont font = base;
        if (run.face) font.setTypeface(run.face);
        if (tracking <= 0.0f) {
            const std::size_t count = run.end - run.begin;
            target->drawSimpleText(text + run.begin, count, SkTextEncoding::kUTF8, pen, y, font, paint);
            pen += font.measureText(text + run.begin, count, SkTextEncoding::kUTF8);
            continue;
        }
        // Tracked: one scalar at a time, the gap after each but the last.
        std::size_t index = run.begin;
        while (index < run.end) {
            const std::size_t start = index;
            decode_utf8(text, length, index);
            target->drawSimpleText(text + start, index - start, SkTextEncoding::kUTF8, pen, y, font, paint);
            pen += font.measureText(text + start, index - start, SkTextEncoding::kUTF8);
            if (index < length) pen += tracking;
        }
    }
}

inline float measure_runs(const SkFont &base, SkTypeface *lent, const char *text, std::size_t length) {
    float total = 0.0f;
    for (const TextRun &run : split_runs(lent, text, length)) {
        SkFont font = base;
        if (run.face) font.setTypeface(run.face);
        total += font.measureText(text + run.begin, run.end - run.begin, SkTextEncoding::kUTF8);
    }
    return total;
}

inline SkFontHinting hinting_for(int hinting) {
    switch (hinting) {
        case 1: return SkFontHinting::kSlight;
        case 2: return SkFontHinting::kNormal;
        case 3: return SkFontHinting::kFull;
        default: return SkFontHinting::kNone;
    }
}

inline SkFont font_for(float size) {
    SkFont font;
    font.setSize(size);
    font.setEdging(SkFont::Edging::kAntiAlias);
    font.setSubpixel(elisa_skia_text_subpixel != 0);
    font.setHinting(hinting_for(elisa_skia_text_hinting));
    return font;
}

// A two-stop gradient down (or across) a box. The STOP POLICY stays in Elisa --
// two evenly spaced stops, no positions supplied -- so this is only the shader
// construction the C++ side has to own.
inline sk_sp<SkShader> three_stop_shader(float x, float y, float width, float height,
                                          SkColor start, SkColor mid, float mid_at, SkColor end,
                                          std::int32_t horizontal) {
    const SkPoint points[] = {
        {x, y},
        {horizontal != 0 ? x + width : x, horizontal != 0 ? y : y + height},
    };
    const SkColor4f colors[] = {SkColor4f::FromColor(start), SkColor4f::FromColor(mid), SkColor4f::FromColor(end)};
    const float positions[] = {0.0f, mid_at, 1.0f};
    const SkGradient gradient({SkSpan(colors), SkSpan(positions), SkTileMode::kClamp}, {});
    return SkShaders::LinearGradient(points, gradient);
}

inline sk_sp<SkShader> two_stop_shader(float x, float y, float width, float height,
                                std::uint8_t start_red, std::uint8_t start_green,
                                std::uint8_t start_blue, std::uint8_t start_alpha,
                                std::uint8_t end_red, std::uint8_t end_green,
                                std::uint8_t end_blue, std::uint8_t end_alpha,
                                std::int32_t horizontal) {
    const SkPoint points[] = {
        {x, y},
        {horizontal != 0 ? x + width : x, horizontal != 0 ? y : y + height},
    };
    const SkColor4f colors[] = {
        SkColor4f::FromColor(color(start_red, start_green, start_blue, start_alpha)),
        SkColor4f::FromColor(color(end_red, end_green, end_blue, end_alpha)),
    };
    const SkGradient gradient({SkSpan(colors), SkTileMode::kClamp}, {});
    return SkShaders::LinearGradient(points, gradient);
}

inline SkFont font_for(float size, SkTypeface *typeface) {
    SkFont font = font_for(size);
    // The FFI handle is borrowed, while SkFont stores an owning sk_sp. Hold a
    // temporary ref for the font's lifetime without transferring host ownership.
    font.setTypeface(sk_ref_sp(typeface));
    return font;
}

// A DESIGNED BOLD IF THE HOST HAS ONE, and the synthetic stroke if it has not.
//
// The weight stroke is the framework's signal that a run is weighted; it is a
// positive number exactly when UiPaint says the run is bold. That makes it the
// switch as well as the amount, so lending the renderer a second face needed no
// change to any drawing or measuring entry point.
inline bool weighted_run(float weight_stroke) {
    return weight_stroke > 0.0f && bounded_extent(weight_stroke);
}

inline bool have_bold_face(float weight_stroke) {
    return weighted_run(weight_stroke) && elisa_skia_bold_typeface != 0;
}

inline SkFont weighted_font_for(float size, std::size_t font_handle, float weight_stroke) {
    const std::size_t chosen = have_bold_face(weight_stroke) ? elisa_skia_bold_typeface : font_handle;
    return font_for(size, reinterpret_cast<SkTypeface *>(chosen));
}

// Weight, from the ONE typeface a host lends the renderer.
//
// A host hands over a single borrowed SkTypeface for the frame, so there is no
// bold face to select and weight has to be synthesized. `setEmbolden` does that
// and is what this bridge used, but the AMOUNT was Skia's rather than the
// framework's -- and measured against a real semibold face it was 30% light. So
// the caller supplies the stem growth and this applies it as a stroke.
//
// A stroke, like embolden, dilates the outline without touching the ADVANCE, so
// a weighted run still occupies exactly the box the layout pass measured for
// it: no second measurement path, no risk of clipped labels.
inline SkPaint weighted_paint(SkPaint paint, float weight_stroke) {
    // A real bold face already carries the weight in its outlines; dilating it
    // as well would double the stem growth and close the counters.
    if (have_bold_face(weight_stroke)) return paint;
    if (!weighted_run(weight_stroke)) return paint;
    paint.setStyle(SkPaint::kStrokeAndFill_Style);
    paint.setStrokeWidth(weight_stroke);
    return paint;
}

}  // namespace elisa_skia_shim

#endif  // ELISA_SKIA_SHIM_COMMON_H_
