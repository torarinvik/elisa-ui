// Raw MotionEvent-to-contact transport; no recognition or widget policy.
#include "../mobile/native_contact_clock.h"
extern "C" void elisa_android_contact(std::size_t native_id, std::int32_t phase,
                                      float x, float y, float timestamp, std::int32_t tool);

static void forward_android_contacts(const AInputEvent* event, float scale) {
    const std::int32_t raw = AMotionEvent_getAction(event);
    const std::int32_t action = raw & AMOTION_EVENT_ACTION_MASK;
    static elisa_contact_clock contact_clock = {0.0, false};
    const float timestamp = elisa_contact_seconds(&contact_clock,
        AMotionEvent_getEventTime(event) / 1000000000.0,
        action == AMOTION_EVENT_ACTION_DOWN);
    const std::size_t count = AMotionEvent_getPointerCount(event);
    const std::int32_t changed = (raw & AMOTION_EVENT_ACTION_POINTER_INDEX_MASK) >>
        AMOTION_EVENT_ACTION_POINTER_INDEX_SHIFT;
    const auto forward = [&](std::size_t index, std::int32_t phase) {
        const std::int32_t id = AMotionEvent_getPointerId(event, index);
        if (id < 0) return;
        // Native event time is monotonic nanoseconds. Coordinates cross in
        // logical points; Android's tool ordinal is translated by Elisa.
        elisa_android_contact(static_cast<std::size_t>(id), phase,
            AMotionEvent_getX(event, index) / scale,
            AMotionEvent_getY(event, index) / scale,
            timestamp,
            AMotionEvent_getToolType(event, index));
    };
    if (action == AMOTION_EVENT_ACTION_MOVE || action == AMOTION_EVENT_ACTION_CANCEL) {
        for (std::size_t index = 0; index < count; ++index)
            forward(index, action == AMOTION_EVENT_ACTION_MOVE ? 1 : 3);
    } else if (changed >= 0 && static_cast<std::size_t>(changed) < count) {
        if (action == AMOTION_EVENT_ACTION_DOWN || action == AMOTION_EVENT_ACTION_POINTER_DOWN)
            forward(static_cast<std::size_t>(changed), 0);
        if (action == AMOTION_EVENT_ACTION_UP || action == AMOTION_EVENT_ACTION_POINTER_UP)
            forward(static_cast<std::size_t>(changed), 2);
    }
}
