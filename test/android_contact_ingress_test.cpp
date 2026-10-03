// Compile the production MotionEvent adapter against deterministic native facts.
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>

constexpr int AMOTION_EVENT_ACTION_MASK = 255;
constexpr int AMOTION_EVENT_ACTION_POINTER_INDEX_MASK = 65280;
constexpr int AMOTION_EVENT_ACTION_POINTER_INDEX_SHIFT = 8;
constexpr int AMOTION_EVENT_ACTION_DOWN = 0;
constexpr int AMOTION_EVENT_ACTION_UP = 1;
constexpr int AMOTION_EVENT_ACTION_MOVE = 2;
constexpr int AMOTION_EVENT_ACTION_CANCEL = 3;
constexpr int AMOTION_EVENT_ACTION_POINTER_DOWN = 5;
constexpr int AMOTION_EVENT_ACTION_POINTER_UP = 6;
struct Pointer { std::int32_t id, tool; float x, y; };
struct AInputEvent {
    std::int32_t action;
    std::int64_t time;
    std::size_t count;
    std::array<Pointer, 3> pointers;
};
static std::int32_t AMotionEvent_getAction(const AInputEvent* e) { return e->action; }
static std::size_t AMotionEvent_getPointerCount(const AInputEvent* e) { return e->count; }
static std::int32_t AMotionEvent_getPointerId(const AInputEvent* e, std::size_t i) { return e->pointers.at(i).id; }
static float AMotionEvent_getX(const AInputEvent* e, std::size_t i) { return e->pointers.at(i).x; }
static float AMotionEvent_getY(const AInputEvent* e, std::size_t i) { return e->pointers.at(i).y; }
static std::int64_t AMotionEvent_getEventTime(const AInputEvent* e) { return e->time; }
static std::int32_t AMotionEvent_getToolType(const AInputEvent* e, std::size_t i) { return e->pointers.at(i).tool; }
#include "../src/platform/android/android_contact_ingress.inc"

struct Fact { std::size_t id; std::int32_t phase; float x, y, time; std::int32_t tool; };
static std::array<Fact, 16> facts;
static std::size_t fact_count;
extern "C" void elisa_android_contact(std::size_t id, std::int32_t phase,
    float x, float y, float time, std::int32_t tool) {
    facts.at(fact_count++) = {id, phase, x, y, time, tool};
}
static int failures;
static void check(const char* name, bool ok) {
    if (!ok) { std::puts(name); ++failures; }
}
int main() {
    AInputEvent e{AMOTION_EVENT_ACTION_POINTER_DOWN | (1 << 8), 1250000000, 2,
        {{{7, 1, 20, 40}, {91, 2, 60, 80}, {0, 0, 0, 0}}}};
    forward_android_contacts(&e, 2);
    check("secondary down forwards changed slot only", fact_count == 1 && facts[0].id == 91 && facts[0].phase == 0);
    check("native coordinates, stream time and stylus source survive", facts[0].x == 30 && facts[0].y == 40 && facts[0].time == 0.0f && facts[0].tool == 2);
    std::swap(e.pointers[0], e.pointers[1]);
    e.action = AMOTION_EVENT_ACTION_MOVE;
    fact_count = 0;
    forward_android_contacts(&e, 2);
    check("all moved pointers preserve IDs after slot reorder", fact_count == 2 && facts[0].id == 91 && facts[1].id == 7 && facts[0].phase == 1 && facts[1].phase == 1);
    e.action = AMOTION_EVENT_ACTION_POINTER_UP | (1 << 8);
    fact_count = 0;
    forward_android_contacts(&e, 2);
    check("secondary up retires changed identity only", fact_count == 1 && facts[0].id == 7 && facts[0].phase == 2);
    e.action = AMOTION_EVENT_ACTION_CANCEL;
    fact_count = 0;
    forward_android_contacts(&e, 2);
    check("native cancellation forwards every live pointer", fact_count == 2 && facts[0].phase == 3 && facts[1].phase == 3);
    e.action = AMOTION_EVENT_ACTION_POINTER_DOWN | (3 << 8);
    fact_count = 0;
    forward_android_contacts(&e, 2);
    check("invalid changed index never reads a pointer", fact_count == 0);
    e.action = AMOTION_EVENT_ACTION_MOVE;
    e.pointers[0].id = -1;
    forward_android_contacts(&e, 2);
    check("negative native identities are rejected", fact_count == 1 && facts[0].id == 7);
    e.action = AMOTION_EVENT_ACTION_DOWN;
    e.count = 1;
    e.pointers[0].id = 7;
    e.time = 100000000000000000LL;
    fact_count = 0;
    forward_android_contacts(&e, 2);
    e.action = AMOTION_EVENT_ACTION_UP;
    e.time += 340000000;
    forward_android_contacts(&e, 2);
    check("long uptime retains tap threshold precision", facts[0].time == 0.0f && std::fabs(facts[1].time - 0.34f) < 0.00001f);
    elisa_contact_clock clock{0.0, false};
    check("UIKit double uptime shares precise clock contract", elisa_contact_seconds(&clock, 100000000.0, true) == 0 && std::fabs(elisa_contact_seconds(&clock, 100000000.61, false) - 0.61f) < 0.00001f);
    check("backward and hostile clocks fail closed", std::isnan(elisa_contact_seconds(&clock, 99999999.0, false)) && std::isnan(elisa_contact_seconds(&clock, INFINITY, false)));
    if (failures == 0) std::puts("android native contacts: all checks passed");
    return failures == 0 ? 0 : 1;
}
