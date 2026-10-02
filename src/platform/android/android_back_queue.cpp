// Android's Java back callback runs on the UI thread, but retained state is
// owned by android_main. Queue each committed back fact and decide it there.

#include <atomic>
#include <cstdint>
#include <android/native_activity.h>

extern "C" void elisa_android_request_frame(void);
extern "C" std::int32_t elisa_android_back(void);
extern "C" void elisa_android_activity_unhandled_back(ANativeActivity *activity);
extern "C" void elisa_android_process_service_results(void);

namespace {

std::atomic<std::uint32_t> pending_back_requests{0};

}

extern "C" void elisa_android_request_back(void) {
    std::uint32_t pending = pending_back_requests.load(std::memory_order_relaxed);
    while (pending < 32 && !pending_back_requests.compare_exchange_weak(
               pending, pending + 1, std::memory_order_release, std::memory_order_relaxed)) {}
    elisa_android_request_frame();
}

extern "C" void elisa_android_process_back_requests(ANativeActivity *activity) {
    const std::uint32_t requests = pending_back_requests.exchange(0, std::memory_order_acquire);
    for (std::uint32_t index = 0; index < requests; ++index) {
        if (elisa_android_back() == 0) elisa_android_activity_unhandled_back(activity);
    }
    elisa_android_process_service_results();
}
