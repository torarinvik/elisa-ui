// Apple-only fragment included inside namespace elisa_skia_shim after the
// shared font-manager state and Skia headers are available.
struct ElisaShapedText {
    sk_sp<SkTextBlob> blob;
    float advance;
    std::size_t glyph_count;
};

class ElisaShapedTextHandler final : public SkShaper::RunHandler {
public:
    explicit ElisaShapedTextHandler(const char *text) : text_(text) {}

    void beginLine() override {
        position_ = {0.0f, next_baseline_};
        line_advance_ = 0.0f;
        ascent_ = descent_ = leading_ = 0.0f;
    }

    void runInfo(const RunInfo &info) override {
        SkFontMetrics metrics;
        info.fFont.getMetrics(&metrics);
        ascent_ = std::min(ascent_, metrics.fAscent);
        descent_ = std::max(descent_, metrics.fDescent);
        leading_ = std::max(leading_, metrics.fLeading);
    }

    void commitRunInfo() override {}

    Buffer runBuffer(const RunInfo &info) override {
        const int count = static_cast<int>(info.glyphCount);
        const int text_bytes = static_cast<int>(info.utf8Range.size());
        const auto &buffer = builder_.allocRunTextPos(info.fFont, count, text_bytes);
        if (buffer.utf8text != nullptr) {
            std::memcpy(buffer.utf8text, text_ + info.utf8Range.begin(), text_bytes);
        }
        clusters_ = buffer.clusters;
        run_glyph_count_ = count;
        cluster_offset_ = info.utf8Range.begin();
        total_glyph_count_ += info.glyphCount;
        return {buffer.glyphs, buffer.points(), nullptr, buffer.clusters, position_};
    }

    void commitRunBuffer(const RunInfo &info) override {
        for (int index = 0; index < run_glyph_count_; ++index) {
            clusters_[index] -= static_cast<std::uint32_t>(cluster_offset_);
        }
        position_ += info.fAdvance;
        line_advance_ += info.fAdvance.fX;
    }

    void commitLine() override {
        max_advance_ = std::max(max_advance_, std::fabs(line_advance_));
        next_baseline_ += descent_ + leading_ - ascent_;
    }

    sk_sp<SkTextBlob> make_blob() { return builder_.make(); }
    float advance() const { return max_advance_; }
    std::size_t glyph_count() const { return total_glyph_count_; }

private:
    SkTextBlobBuilder builder_;
    const char *text_;
    std::uint32_t *clusters_ = nullptr;
    int run_glyph_count_ = 0;
    std::size_t cluster_offset_ = 0;
    std::size_t total_glyph_count_ = 0;
    SkPoint position_ = {0.0f, 0.0f};
    SkScalar line_advance_ = 0.0f;
    SkScalar max_advance_ = 0.0f;
    SkScalar next_baseline_ = 0.0f;
    SkScalar ascent_ = 0.0f;
    SkScalar descent_ = 0.0f;
    SkScalar leading_ = 0.0f;
};

constexpr std::size_t max_shaped_text_cache_entries = 64;
constexpr std::size_t max_shaped_text_cache_bytes = 1024 * 1024;
constexpr std::size_t max_shaped_text_cache_entry_bytes = 64 * 1024;

struct ShapedTextCacheEntry {
    SkFont font;
    std::uint32_t typeface_id;
    std::uintptr_t font_manager;
    std::uint32_t locale_revision;
    std::uint32_t scale_generation;
    std::string text;
    ElisaShapedText shaped;
    std::size_t estimated_bytes;
};

inline std::list<ShapedTextCacheEntry> elisa_skia_shaped_text_cache;
inline std::size_t elisa_skia_shaped_text_cache_bytes = 0;
inline std::uint32_t elisa_skia_shaped_text_cache_locale_revision = 0;
inline std::uint32_t elisa_skia_shaped_text_cache_scale_generation = 0;
inline std::uint64_t elisa_skia_shaped_text_cache_hits = 0;
inline std::uint64_t elisa_skia_shaped_text_cache_misses = 0;

inline void clear_shaped_text_cache() {
    elisa_skia_shaped_text_cache.clear();
    elisa_skia_shaped_text_cache_bytes = 0;
    clear_simple_text_cache();
}

inline void set_shaped_text_cache_context(std::uint32_t locale_revision,
                                           std::uint32_t scale_generation) {
    if (locale_revision != elisa_skia_shaped_text_cache_locale_revision ||
        scale_generation != elisa_skia_shaped_text_cache_scale_generation) {
        clear_shaped_text_cache();
        elisa_skia_shaped_text_cache_locale_revision = locale_revision;
        elisa_skia_shaped_text_cache_scale_generation = scale_generation;
    }
    set_simple_text_cache_context(locale_revision, scale_generation);
}

inline ElisaShapedText shape_text_uncached(const SkFont &font, const char *text,
                                            std::size_t length) {
    static const std::unique_ptr<SkShaper> shaper = SkShaper::Make();
    if (!shaper) return {nullptr, 0.0f, 0};
    sk_sp<SkFontMgr> fallback = elisa_skia_font_manager != 0
        ? sk_ref_sp(reinterpret_cast<SkFontMgr *>(elisa_skia_font_manager))
        : SkFontMgr::RefEmpty();
    auto font_runs = SkShaper::MakeFontMgrRunIterator(text, length, font, std::move(fallback));
    auto bidi_runs = SkShaper::MakeBiDiRunIterator(text, length, 0);
    auto script_runs = SkShaper::MakeScriptRunIterator(text, length, 0);
    auto language_runs = SkShaper::MakeStdLanguageRunIterator(text, length);
    if (!font_runs || !bidi_runs || !script_runs || !language_runs) return {nullptr, 0.0f, 0};
    ElisaShapedTextHandler handler(text);
    // Avoid the m150 convenience overload's null-manager CoreText path.
    shaper->shape(text, length, *font_runs, *bidi_runs, *script_runs,
                  *language_runs, 1.0e9f, &handler);
    return {handler.make_blob(), handler.advance(), handler.glyph_count()};
}

inline ElisaShapedText shape_text(const SkFont &font, const char *text, std::size_t length) {
    const SkTypefaceID typeface_id = font.getTypeface()->uniqueID();
    const auto manager = reinterpret_cast<std::uintptr_t>(elisa_skia_font_manager);
    const auto matches = [&](const ShapedTextCacheEntry &entry) {
        return entry.typeface_id == typeface_id && entry.font_manager == manager &&
            entry.locale_revision == elisa_skia_shaped_text_cache_locale_revision &&
            entry.scale_generation == elisa_skia_shaped_text_cache_scale_generation &&
            entry.font == font && entry.text.size() == length &&
            std::memcmp(entry.text.data(), text, length) == 0;
    };
    for (auto entry = elisa_skia_shaped_text_cache.begin();
         entry != elisa_skia_shaped_text_cache.end(); ++entry) {
        if (matches(*entry)) {
            ++elisa_skia_shaped_text_cache_hits;
            elisa_skia_shaped_text_cache.splice(elisa_skia_shaped_text_cache.begin(),
                                                 elisa_skia_shaped_text_cache, entry);
            return elisa_skia_shaped_text_cache.front().shaped;
        }
    }

    ++elisa_skia_shaped_text_cache_misses;
    ElisaShapedText shaped = shape_text_uncached(font, text, length);
    if (!shaped.blob) return shaped;
    // SkTextBlob has no byte-size query; overestimate each glyph's positions,
    // IDs, cluster and run storage. Oversized runs are returned, not cached.
    const std::size_t estimated_bytes = 512 + length + shaped.glyph_count * 64;
    if (estimated_bytes > max_shaped_text_cache_entry_bytes) return shaped;
    elisa_skia_shaped_text_cache.push_front(ShapedTextCacheEntry{
        font, typeface_id, manager, elisa_skia_shaped_text_cache_locale_revision,
        elisa_skia_shaped_text_cache_scale_generation, std::string(text, length),
        shaped, estimated_bytes});
    elisa_skia_shaped_text_cache_bytes += estimated_bytes;
    while (elisa_skia_shaped_text_cache.size() > max_shaped_text_cache_entries ||
           elisa_skia_shaped_text_cache_bytes > max_shaped_text_cache_bytes) {
        elisa_skia_shaped_text_cache_bytes -= elisa_skia_shaped_text_cache.back().estimated_bytes;
        elisa_skia_shaped_text_cache.pop_back();
    }
    return shaped;
}
