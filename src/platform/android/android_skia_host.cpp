// The Android host: a NativeActivity that owns a window, an input queue and
// two fonts, and hands each frame to Elisa as a Skia canvas.
//
// Everything visible is Elisa's. This file locks the window's buffer, wraps
// it in a raster surface, and calls the backend's entry points; it decides
// nothing about appearance. What it does decide is what UIKit decides for
// iOS: when a touch has become a drag. A finger that moves past the slop
// cancels the press it began and scrolls whatever is under it from then on,
// so a tap stays a tap and a drag scrolls.

#include <android/configuration.h>
#include <android/input.h>
#include <android/log.h>
#include <sys/system_properties.h>
#include <android/native_window.h>
#include <android_native_app_glue.h>

#include <chrono>
#include <cmath>
#include <cstring>
#include <cstddef>
#include <cstdint>

#include "include/core/SkCanvas.h"
#include "include/core/SkColor.h"
#include "include/core/SkFontMgr.h"
#include "include/core/SkFontStyle.h"
#include "include/core/SkImage.h"
#include "include/core/SkImageInfo.h"
#include "include/core/SkPixmap.h"
#include "include/core/SkSurface.h"
#include "include/core/SkTypeface.h"
#include "include/ports/SkFontMgr_android.h"
#include "include/ports/SkFontScanner_FreeType.h"

#include "../../../examples/storefront/pictures_skia.h"

extern "C" void elisa_skia_set_bold_typeface(std::size_t font);
extern "C" void elisa_skia_set_font_manager(std::size_t manager);
extern "C" std::int32_t elisa_android_start(float width, float height, float scale, float top,
                                            float right, float bottom, float left);
extern "C" std::int32_t elisa_android_resize(float width, float height, float scale, float top,
                                             float right, float bottom, float left);
extern "C" void elisa_android_stop(void);
extern "C" std::int32_t elisa_android_render(std::size_t canvas, std::size_t font, float width,
                                             float height, float scale);
extern "C" float elisa_android_frame_delay(void);
extern "C" void elisa_android_touch(std::int32_t phase, float x, float y);
extern "C" void elisa_android_scroll(float x, float y, float dx, float dy);
// An application that takes pictures defines this; one that does not, does
// not, and the weak reference is null.
extern "C" std::int32_t elisa_android_pictures(std::size_t brand, std::size_t glyph,
                                               std::size_t banner, std::size_t plate,
                                               std::size_t grain) __attribute__((weak));

#define ELISA_LOG(...) __android_log_print(ANDROID_LOG_INFO, "elisa-ui", __VA_ARGS__)

// Two lines a run -- the surface it woke up on, and whether the pictures took
// -- are worth printing always: they are the first thing to read when a device
// shows a blank window. A line a frame is not, so the frame and gesture traces
// wait behind a property nobody sets by accident:
//
//     adb shell setprop debug.elisa.trace 1
//
// read once, because a property read per frame is itself a cost.
namespace {
bool tracing() {
    static const bool on = [] {
        char value[PROP_VALUE_MAX] = {0};
        return __system_property_get("debug.elisa.trace", value) > 0 && value[0] != '0';
    }();
    return on;
}
}  // namespace

#define ELISA_TRACE(...) do { if (tracing()) ELISA_LOG(__VA_ARGS__); } while (false)

namespace {
// How many different colours a sparse walk of the frame finds, capped. One
// number, cheap to compute and impossible to fake: a window that came up blank
// reports 1, and a window showing the storefront reports hundreds. The stride
// is prime so it does not fall into step with the row width and walk a column.
int sampled_colors(const SkPixmap& pixels) {
    if (pixels.addr() == nullptr || pixels.width() <= 0 || pixels.height() <= 0) return 0;
    constexpr int kSlots = 1024;
    std::uint32_t seen[kSlots] = {0};
    bool used[kSlots] = {false};
    int distinct = 0;
    const int width = pixels.width();
    for (std::int64_t index = 0; index < static_cast<std::int64_t>(width) * pixels.height(); index += 997) {
        const int y = static_cast<int>(index / width);
        const std::uint32_t value = *reinterpret_cast<const std::uint32_t*>(
            static_cast<const std::uint8_t*>(pixels.addr()) + static_cast<std::size_t>(y) * pixels.rowBytes() +
            static_cast<std::size_t>(index % width) * 4);
        int slot = static_cast<int>((value * 2654435761u) >> 22) & (kSlots - 1);
        while (used[slot] && seen[slot] != value) slot = (slot + 1) & (kSlots - 1);
        if (used[slot]) continue;
        used[slot] = true;
        seen[slot] = value;
        if (++distinct == kSlots - 1) break;
    }
    return distinct;
}
}  // namespace

namespace {

struct Host {
    android_app* app = nullptr;
    sk_sp<SkFontMgr> font_manager;
    sk_sp<SkTypeface> regular;
    sk_sp<SkTypeface> bold;
    sk_sp<SkImage> brand, glyph, banner, plate, grain;
    // The frame is painted here, in ordinary memory, and copied into the
    // window's buffer afterwards. A locked window buffer is write-combined:
    // every blend and every blur reads the destination back, and reading
    // write-combined memory is what turned a frame into three quarters of
    // a second.
    sk_sp<SkSurface> frame;
    float scale = 1.0f;
    bool started = false;
    bool needs_frame = true;
    // The touch that may become a drag.
    bool touching = false;
    bool panning = false;
    float down_x = 0.0f, down_y = 0.0f;
    float last_x = 0.0f, last_y = 0.0f;
};

const int kTouchDown = 0, kTouchMove = 1, kTouchUp = 2, kTouchCancel = 3;

float density_scale(android_app* app) {
    const std::int32_t density = AConfiguration_getDensity(app->config);
    if (density <= 0 || density == ACONFIGURATION_DENSITY_NONE) return 1.0f;
    return static_cast<float>(density) / 160.0f;
}

void lend_fonts(Host& host) {
    if (host.font_manager) return;
    host.font_manager = SkFontMgr_New_Android(nullptr, SkFontScanner_Make_FreeType());
    if (!host.font_manager) return;
    // The system sans: Roboto on a Pixel, whatever the device ships elsewhere.
    host.regular = host.font_manager->matchFamilyStyle("sans-serif", SkFontStyle::Normal());
    host.bold = host.font_manager->matchFamilyStyle("sans-serif", SkFontStyle::Bold());
    if (!host.regular) host.regular = host.font_manager->legacyMakeTypeface(nullptr, SkFontStyle::Normal());
    elisa_skia_set_bold_typeface(reinterpret_cast<std::size_t>(host.bold.get()));
    elisa_skia_set_font_manager(reinterpret_cast<std::size_t>(host.font_manager.get()));
}

void lend_pictures(Host& host) {
    if (elisa_android_pictures == nullptr || host.banner) return;
    host.banner = elisa_storefront_pictures::make_scene(720, 240, 150, 190, 250);
    host.plate = elisa_storefront_pictures::make_scene(360, 180, 170, 160, 235);
    host.brand = elisa_storefront_pictures::make_glyph();
    host.glyph = elisa_storefront_pictures::make_glyph();
    host.grain = elisa_storefront_pictures::make_grain();
    const std::int32_t bound = elisa_android_pictures(
        reinterpret_cast<std::size_t>(host.brand.get()), reinterpret_cast<std::size_t>(host.glyph.get()),
        reinterpret_cast<std::size_t>(host.banner.get()), reinterpret_cast<std::size_t>(host.plate.get()),
        reinterpret_cast<std::size_t>(host.grain.get()));
    ELISA_LOG("pictures -> %d", bound);
}

void start_or_resize(Host& host) {
    ANativeWindow* window = host.app->window;
    if (window == nullptr) return;
    host.scale = density_scale(host.app);
    const float width = static_cast<float>(ANativeWindow_getWidth(window)) / host.scale;
    const float height = static_cast<float>(ANativeWindow_getHeight(window)) / host.scale;
    ANativeWindow_setBuffersGeometry(window, 0, 0, WINDOW_FORMAT_RGBA_8888);
    lend_fonts(host);
    // The content rect is what is not under a system bar. Until Android has
    // reported one it is empty, and empty means no inset.
    const ARect& content = host.app->contentRect;
    float top = 0.0f, right = 0.0f, bottom = 0.0f, left = 0.0f;
    if (content.right > content.left && content.bottom > content.top) {
        top = static_cast<float>(content.top) / host.scale;
        left = static_cast<float>(content.left) / host.scale;
        right = width - static_cast<float>(content.right) / host.scale;
        bottom = height - static_cast<float>(content.bottom) / host.scale;
        if (right < 0.0f) right = 0.0f;
        if (bottom < 0.0f) bottom = 0.0f;
    }
    if (!host.started) {
        host.started = elisa_android_start(width, height, host.scale, top, right, bottom, left) == 1;
        ELISA_LOG("start %gx%g @%g insets %g %g %g %g -> %d", width, height, host.scale, top, right,
                  bottom, left, host.started ? 1 : 0);
    } else {
        elisa_android_resize(width, height, host.scale, top, right, bottom, left);
    }
    host.needs_frame = true;
}

void draw(Host& host) {
    ANativeWindow* window = host.app->window;
    if (window == nullptr || !host.started) return;
    ANativeWindow_Buffer buffer;
    if (ANativeWindow_lock(window, &buffer, nullptr) != 0) return;
    const SkImageInfo info = SkImageInfo::Make(buffer.width, buffer.height, kRGBA_8888_SkColorType,
                                               kPremul_SkAlphaType);
    if (!host.frame || host.frame->width() != buffer.width || host.frame->height() != buffer.height) {
        host.frame = SkSurfaces::Raster(info);
    }
    if (host.frame) {
        const auto began = std::chrono::steady_clock::now();
        SkCanvas* canvas = host.frame->getCanvas();
        canvas->clear(SK_ColorBLACK);
        const std::int32_t status = elisa_android_render(
            reinterpret_cast<std::size_t>(canvas), reinterpret_cast<std::size_t>(host.regular.get()),
            static_cast<float>(buffer.width) / host.scale, static_cast<float>(buffer.height) / host.scale,
            host.scale);
        SkPixmap pixels;
        if (host.frame->peekPixels(&pixels)) {
            const std::size_t row_bytes = static_cast<std::size_t>(buffer.width) * 4;
            for (int y = 0; y < buffer.height; ++y) {
                std::memcpy(static_cast<std::uint8_t*>(buffer.bits) + static_cast<std::size_t>(y) * buffer.stride * 4,
                            static_cast<const std::uint8_t*>(pixels.addr()) + static_cast<std::size_t>(y) * pixels.rowBytes(), row_bytes);
            }
        }
        const auto took = std::chrono::duration_cast<std::chrono::milliseconds>(
                              std::chrono::steady_clock::now() - began).count();
        ELISA_TRACE("frame %dx%d status=%d colors=%d in %lld ms", buffer.width, buffer.height, status,
                    tracing() ? sampled_colors(pixels) : 0, static_cast<long long>(took));
    }
    ANativeWindow_unlockAndPost(window);
    host.needs_frame = elisa_android_frame_delay() > 0.0f;
    // Pictures after the first frame, the way the Skia fixture binds them.
    if (!host.banner) {
        lend_pictures(host);
        host.needs_frame = true;
    }
}

void on_command(android_app* app, std::int32_t command) {
    Host& host = *static_cast<Host*>(app->userData);
    switch (command) {
        case APP_CMD_INIT_WINDOW:
        case APP_CMD_WINDOW_RESIZED:
        case APP_CMD_CONFIG_CHANGED:
        case APP_CMD_CONTENT_RECT_CHANGED:
            start_or_resize(host);
            break;
        case APP_CMD_TERM_WINDOW:
            break;
        case APP_CMD_GAINED_FOCUS:
        case APP_CMD_WINDOW_REDRAW_NEEDED:
            host.needs_frame = true;
            break;
        case APP_CMD_DESTROY:
            elisa_android_stop();
            host.started = false;
            break;
        default:
            break;
    }
}

std::int32_t on_input(android_app* app, AInputEvent* event) {
    Host& host = *static_cast<Host*>(app->userData);
    if (AInputEvent_getType(event) != AINPUT_EVENT_TYPE_MOTION) return 0;
    const std::int32_t action = AMotionEvent_getAction(event) & AMOTION_EVENT_ACTION_MASK;
    const float x = AMotionEvent_getX(event, 0) / host.scale;
    const float y = AMotionEvent_getY(event, 0) / host.scale;
    // Past this many logical points a touch is a drag, not a press.
    const float slop = 8.0f;
    ELISA_TRACE("motion action=%d at %g,%g panning=%d", action, x, y, host.panning ? 1 : 0);
    switch (action) {
        case AMOTION_EVENT_ACTION_DOWN:
            host.touching = true;
            host.panning = false;
            host.down_x = host.last_x = x;
            host.down_y = host.last_y = y;
            elisa_android_touch(kTouchDown, x, y);
            break;
        case AMOTION_EVENT_ACTION_MOVE:
            if (!host.touching) break;
            if (!host.panning && std::hypot(x - host.down_x, y - host.down_y) > slop) {
                host.panning = true;
                elisa_android_touch(kTouchCancel, x, y);
            }
            if (host.panning) {
                elisa_android_scroll(x, y, x - host.last_x, y - host.last_y);
            } else {
                elisa_android_touch(kTouchMove, x, y);
            }
            host.last_x = x;
            host.last_y = y;
            break;
        case AMOTION_EVENT_ACTION_UP:
            if (!host.panning) elisa_android_touch(kTouchUp, x, y);
            host.touching = host.panning = false;
            break;
        case AMOTION_EVENT_ACTION_CANCEL:
            if (!host.panning) elisa_android_touch(kTouchCancel, x, y);
            host.touching = host.panning = false;
            break;
        default:
            return 0;
    }
    host.needs_frame = true;
    return 1;
}

}  // namespace

void android_main(android_app* app) {
    Host host;
    host.app = app;
    app->userData = &host;
    app->onAppCmd = on_command;
    app->onInputEvent = on_input;
    while (true) {
        int events = 0;
        android_poll_source* source = nullptr;
        // Block while idle; wake for the next animated frame; spin while a
        // frame is owed.
        int timeout = -1;
        if (host.needs_frame) {
            timeout = 0;
        } else {
            const float delay = elisa_android_frame_delay();
            if (delay > 0.0f) timeout = static_cast<int>(delay * 1000.0f);
        }
        const int result = ALooper_pollOnce(timeout, nullptr, &events, reinterpret_cast<void**>(&source));
        if (result == ALOOPER_POLL_ERROR) break;
        if (source != nullptr) source->process(app, source);
        if (app->destroyRequested != 0) break;
        if (host.needs_frame || elisa_android_frame_delay() > 0.0f) draw(host);
    }
}
