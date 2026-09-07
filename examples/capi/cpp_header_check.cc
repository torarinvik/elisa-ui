/* C++ consumers get the same C linkage and layout guarantees. */
#include <cstddef>

#include "elisa_ui.h"

static_assert(sizeof(elisa_ui_event) == 24, "event record size changed");
static_assert(offsetof(elisa_ui_event, code) == 20, "event code offset changed");
static_assert(ELISA_UI_EVENT_FOCUS_LOST == 13, "event ordinals changed");
static_assert(ELISA_UI_ABI_VERSION == 0x000100u, "ABI version changed");

int main() {
    return elisa_ui_abi_version() == ELISA_UI_ABI_VERSION ? 0 : 1;
}
