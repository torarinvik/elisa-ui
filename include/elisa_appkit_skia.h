/* elisa-ui: optional AppKit presentation bridge for the Skia custom backend. */
#ifndef ELISA_APPKIT_SKIA_H
#define ELISA_APPKIT_SKIA_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* The AppKit host owns the CGContext and the temporary SkSurface. Elisa owns
 * frame preparation/replay through this callback and the callback's borrowed
 * SkCanvas/typeface handles. A positive result means the context was painted;
 * zero means Skia was rejected before Elisa consumed a frame and the caller
 * may use its normal fallback path. A negative result means Elisa already ran
 * the frame callback (either the frame could not be presented or the native
 * presentation failed); the caller must not replay the frame through another
 * backend because that could duplicate application mutations. */
int32_t elisa_appkit_canvas_skia_present(size_t window_handle, size_t context,
                                         float logical_width, float logical_height,
                                         float pixel_width, float pixel_height);

#ifdef __cplusplus
}
#endif

#endif /* ELISA_APPKIT_SKIA_H */
