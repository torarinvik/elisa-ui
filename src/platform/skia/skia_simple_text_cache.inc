// Bounded cache for the simple-text fallback used on non-Apple profiles and
// when Apple shaping is unavailable. Tracked text keeps its scalar draw path
// and bypasses this cache. The blobs retain glyph IDs and font attributes; run
// splitting and fallback selection happen only on a miss. Paint and origin
// stay draw-time inputs.
struct ElisaSimpleTextRun {
    sk_sp<SkTextBlob> blob;
    float advance;
};

struct ElisaSimpleTextLayout {
    std::vector<ElisaSimpleTextRun> runs;
    float advance = 0.0f;
};

constexpr std::size_t max_simple_text_cache_entries = 64;
constexpr std::size_t max_simple_text_cache_bytes = 1024 * 1024;
constexpr std::size_t max_simple_text_cache_entry_bytes = 64 * 1024;

struct SimpleTextCacheEntry {
    SkFont font;
    std::uint32_t typeface_id;
    std::uintptr_t font_manager;
    std::uint32_t locale_revision;
    std::uint32_t scale_generation;
    std::string text;
    ElisaSimpleTextLayout layout;
    std::size_t estimated_bytes;
};

inline std::list<SimpleTextCacheEntry> elisa_skia_simple_text_cache;
inline std::size_t elisa_skia_simple_text_cache_bytes = 0;
inline std::uint32_t elisa_skia_simple_text_cache_locale_revision = 0;
inline std::uint32_t elisa_skia_simple_text_cache_scale_generation = 0;
inline std::uint64_t elisa_skia_simple_text_cache_hits = 0;
inline std::uint64_t elisa_skia_simple_text_cache_misses = 0;

inline void clear_simple_text_cache() {
    elisa_skia_simple_text_cache.clear();
    elisa_skia_simple_text_cache_bytes = 0;
}

inline void set_simple_text_cache_context(std::uint32_t locale_revision,
                                          std::uint32_t scale_generation) {
    if (locale_revision != elisa_skia_simple_text_cache_locale_revision ||
        scale_generation != elisa_skia_simple_text_cache_scale_generation) {
        clear_simple_text_cache();
        elisa_skia_simple_text_cache_locale_revision = locale_revision;
        elisa_skia_simple_text_cache_scale_generation = scale_generation;
    }
}

inline bool make_simple_text_layout(const SkFont &base, SkTypeface *lent,
                                    const char *text, std::size_t length,
                                    ElisaSimpleTextLayout &layout) {
    layout = {};
    for (const TextRun &run : split_runs(lent, text, length)) {
        SkFont font = base;
        if (run.face) font.setTypeface(run.face);
        const std::size_t count = run.end - run.begin;
        sk_sp<SkTextBlob> blob = SkTextBlob::MakeFromText(
            text + run.begin, count, font, SkTextEncoding::kUTF8);
        if (!blob) {
            layout = {};
            return false;
        }
        const float advance = font.measureText(text + run.begin, count, SkTextEncoding::kUTF8);
        layout.runs.push_back(ElisaSimpleTextRun{std::move(blob), advance});
        layout.advance += advance;
    }
    return !layout.runs.empty();
}

// On a hit, the returned pointer remains valid until this cache is mutated.
// Callers consume it synchronously; an uncached oversized result is returned
// through caller-owned storage instead.
inline const ElisaSimpleTextLayout *simple_text_layout_for(
    const SkFont &font, SkTypeface *lent, const char *text, std::size_t length,
    ElisaSimpleTextLayout &uncached) {
    const SkTypeface *typeface = font.getTypeface();
    const std::uint32_t typeface_id = typeface != nullptr ? typeface->uniqueID() : 0;
    const auto manager = reinterpret_cast<std::uintptr_t>(elisa_skia_font_manager);
    const auto matches = [&](const SimpleTextCacheEntry &entry) {
        return entry.typeface_id == typeface_id && entry.font_manager == manager &&
            entry.locale_revision == elisa_skia_simple_text_cache_locale_revision &&
            entry.scale_generation == elisa_skia_simple_text_cache_scale_generation &&
            entry.font == font && entry.text.size() == length &&
            std::memcmp(entry.text.data(), text, length) == 0;
    };
    for (auto entry = elisa_skia_simple_text_cache.begin();
         entry != elisa_skia_simple_text_cache.end(); ++entry) {
        if (matches(*entry)) {
            ++elisa_skia_simple_text_cache_hits;
            elisa_skia_simple_text_cache.splice(elisa_skia_simple_text_cache.begin(),
                                                 elisa_skia_simple_text_cache, entry);
            return &elisa_skia_simple_text_cache.front().layout;
        }
    }

    ++elisa_skia_simple_text_cache_misses;
    ElisaSimpleTextLayout layout;
    if (!make_simple_text_layout(font, lent, text, length, layout)) return nullptr;
    // SkTextBlob has no byte-size query. This conservative estimate charges
    // per input byte (upper-bounding UTF-8 scalar/glyph count) plus each run.
    const std::size_t estimated_bytes = 512 + length * 64 + layout.runs.size() * 256;
    if (estimated_bytes > max_simple_text_cache_entry_bytes) {
        uncached = std::move(layout);
        return &uncached;
    }
    elisa_skia_simple_text_cache.push_front(SimpleTextCacheEntry{
        font, typeface_id, manager, elisa_skia_simple_text_cache_locale_revision,
        elisa_skia_simple_text_cache_scale_generation, std::string(text, length),
        std::move(layout), estimated_bytes});
    elisa_skia_simple_text_cache_bytes += estimated_bytes;
    while (elisa_skia_simple_text_cache.size() > max_simple_text_cache_entries ||
           elisa_skia_simple_text_cache_bytes > max_simple_text_cache_bytes) {
        elisa_skia_simple_text_cache_bytes -=
            elisa_skia_simple_text_cache.back().estimated_bytes;
        elisa_skia_simple_text_cache.pop_back();
    }
    return &elisa_skia_simple_text_cache.front().layout;
}

inline void draw_simple_text_layout(SkCanvas *target, const ElisaSimpleTextLayout &layout,
                                   const SkPaint &paint, float x, float y) {
    float pen = x;
    for (const ElisaSimpleTextRun &run : layout.runs) {
        target->drawTextBlob(run.blob.get(), pen, y, paint);
        pen += run.advance;
    }
}
