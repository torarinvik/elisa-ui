// Exercise the production owner-thread synchronizer, not a duplicate policy.
#include <cstdint>
#include <cstdio>
using ANativeActivity = void;
struct App { void* activity; };
struct Host { App* app; bool keyboard = false; int keyboard_purpose = 1; std::uint64_t keyboard_owner = 0; };
static std::uint64_t owner = 1, published_owner;
extern "C" std::uint64_t elisa_android_ime_owner() { return owner; }
extern "C" void elisa_android_ime_publish_owner(std::uint64_t value) { published_owner = value; }
static bool wanted;
static int purpose = 1, published = -1, shows, hides, publication_at_show = -1, published_ready;
static int elisa_android_wants_keyboard() { return wanted ? 1 : 0; }
extern "C" int elisa_android_text_purpose() { return purpose; }
static int selection_start = 4, selection_end = 2, published_start, published_end;
extern "C" std::int32_t elisa_android_ime_selection_position(std::int32_t endpoint) { return endpoint == 0 ? selection_start : selection_end; }
extern "C" std::int32_t elisa_android_ime_publish_state(std::uint64_t token, std::int32_t value, std::int32_t start, std::int32_t end) { bool changed = published_owner != token || published != value || published_start != start || published_end != end; published_owner = token; published = value; published_ready = token != 0; published_start = start; published_end = end; return changed; }
static int selection_updates;
extern "C" void elisa_android_ime_update_selection(ANativeActivity*) { ++selection_updates; }
static void elisa_android_ime_show_keyboard(void*) { ++shows; publication_at_show = published; }
static void elisa_android_ime_hide_keyboard(void*) { ++hides; }
#include "../src/platform/android/android_keyboard_sync.inc"
static int failures;
static void check(const char* name, bool ok) {
    if (!ok) { ++failures; std::puts(name); }
}
int main() {
    App app{nullptr};
    Host host{&app};
    sync_android_keyboard(host);
    check("inactive frame publishes safe traits without showing", published == 1 && published_ready == 0 && shows == 0 && hides == 0);
    wanted = true;
    purpose = 2;
    sync_android_keyboard(host);
    check("focus publishes purpose before requesting native show", shows == 1 && publication_at_show == 2 && host.keyboard && published_ready == 1);
    for (int frame = 0; frame < 100; ++frame) sync_android_keyboard(host);
    check("unchanged editing frames do not restart IME", shows == 1);
    check("owner published before connection creation", published_owner == owner);
    check("selection endpoints publish with connection identity", published_start == 4 && published_end == 2);
    selection_start = 6; selection_end = 1;
    sync_android_keyboard(host);
    check("selection change republishes without restarting keyboard", published_start == 6 && published_end == 1 && shows == 1);
    check("selection-only change notifies IME once", selection_updates == 2);
    purpose = 1;
    sync_android_keyboard(host);
    check("active privacy change republishes before restart", shows == 2 && publication_at_show == 1);
    purpose = 4;
    sync_android_keyboard(host);
    check("active numeric purpose restarts input connection", shows == 3 && publication_at_show == 4);
    wanted = false;
    purpose = 1;
    sync_android_keyboard(host);
    check("blur hides once and publishes nonediting privacy", hides == 1 && !host.keyboard && published == 1 && published_ready == 0);
    for (int frame = 0; frame < 100; ++frame) sync_android_keyboard(host);
    check("inactive frames do not repeat hide requests", hides == 1 && shows == 3);
    wanted = true;
    purpose = 2;
    sync_android_keyboard(host);
    retire_android_keyboard(host);
    check("interruption atomically retires readiness and hides", published_ready == 0 && !host.keyboard && hides == 2);
    retire_android_keyboard(host);
    check("repeated retirement is idempotent", hides == 2);
    sync_android_keyboard(host);
    check("restored editing republishes before new show", published_ready == 1 && publication_at_show == 2 && shows == 5);
    ++owner;
    sync_android_keyboard(host);
    check("same-purpose owner change restarts connection", shows == 6 && published_owner == owner && host.keyboard_owner == owner);
    retire_android_keyboard(host);
    check("retirement closes published owner", published_owner == 0 && host.keyboard_owner == 0);
    if (failures == 0) std::puts("android keyboard sync: all checks passed");
    return failures == 0 ? 0 : 1;
}
