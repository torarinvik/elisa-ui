extern "C" int elisa_android_text_purpose();
extern "C" std::int32_t elisa_android_ime_publish_state(std::uint64_t owner, std::int32_t purpose, std::int32_t start, std::int32_t end);
extern "C" void elisa_android_ime_update_selection(ANativeActivity* activity);
extern "C" std::int32_t elisa_android_ime_selection_position(std::int32_t endpoint);
extern "C" std::uint64_t elisa_android_ime_owner();
extern "C" void elisa_android_ime_publish_owner(std::uint64_t owner);
extern "C" void elisa_android_ime_drain();

static void sync_android_keyboard(Host& host) {
    const bool wanted = elisa_android_wants_keyboard() != 0;
    const int purpose = elisa_android_text_purpose();
    const std::uint64_t owner = wanted ? elisa_android_ime_owner() : 0;
    const bool selection_changed = elisa_android_ime_publish_state(owner, purpose, elisa_android_ime_selection_position(0), elisa_android_ime_selection_position(1)) != 0;
    const bool changed = host.keyboard_purpose != purpose || host.keyboard_owner != owner;
    host.keyboard_owner = owner;
    host.keyboard_purpose = purpose;
    if (wanted != host.keyboard || (wanted && changed)) {
        host.keyboard = wanted;
        if (wanted) elisa_android_ime_show_keyboard(host.app->activity);
        else elisa_android_ime_hide_keyboard(host.app->activity);
    }
    if (owner && selection_changed) elisa_android_ime_update_selection(host.app->activity);
}

static void retire_android_keyboard(Host& host) {
    elisa_android_ime_publish_state(0, 1, 0, 0);
    host.keyboard_owner = 0;
    if (host.keyboard) elisa_android_ime_hide_keyboard(host.app->activity);
    host.keyboard = false;
    host.keyboard_purpose = 1;
}
