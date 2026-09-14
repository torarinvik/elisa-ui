#pragma once

#include <cstdint>

#include "include/core/SkPixmap.h"
#include "include/core/SkSurface.h"

inline std::uint64_t showcase_pixel_region_hash(SkSurface* surface) {
    SkPixmap pixels;
    if (!surface->peekPixels(&pixels)) return 0;
    std::uint64_t hash = 14695981039346656037ull;
    for (int y = 0; y < pixels.height(); ++y) {
        for (int x = 0; x < pixels.width(); ++x) {
            hash ^= pixels.getColor(x, y);
            hash *= 1099511628211ull;
        }
    }
    return hash;
}
