#pragma once

#include <android/native_activity.h>
#include <cstdint>

extern "C" std::int32_t elisa_android_process_accessibility_actions(void);
extern "C" void elisa_android_accessibility_attach(ANativeActivity *activity);
