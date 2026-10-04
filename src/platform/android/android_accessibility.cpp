// Immutable semantic snapshots and queued actions for Android's virtual tree.
// Elisa owns the retained UI on android_main; the framework UI thread only
// reads a copied snapshot and returns bounded action requests here.

#include <android/native_activity.h>
#include <jni.h>

#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <vector>

extern "C" void elisa_android_request_frame(void);
extern "C" std::int32_t elisa_android_accessibility_action(std::uint32_t id,
                                                            std::int32_t kind,
                                                            float value);

namespace {

constexpr std::size_t kActionCapacity = 64;
constexpr std::uint32_t kMaxVirtualId = 256;
constexpr std::size_t kHeaderBytes = 8;
constexpr std::size_t kRecordBytes = 120;
constexpr std::size_t kSnapshotCapacity = kHeaderBytes + kMaxVirtualId * kRecordBytes + 3 * 1024;

struct Action {
    std::uint32_t id;
    std::int32_t kind;
    float value;
};

std::mutex state_mutex;
ANativeActivity *active_activity = nullptr;
std::vector<std::uint8_t> semantic_snapshot;
std::array<Action, kActionCapacity> pending_actions{};
std::size_t action_head = 0;
std::size_t action_count = 0;

bool clear_exception(JNIEnv *env) {
    if (env == nullptr || env->ExceptionCheck() != JNI_TRUE) return false;
    env->ExceptionClear();
    return true;
}

void notify_java(ANativeActivity *activity) {
    if (activity == nullptr || activity->vm == nullptr || activity->clazz == nullptr) return;
    JNIEnv *env = nullptr;
    bool attached = false;
    const jint status = activity->vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6);
    if (status == JNI_EDETACHED) {
        if (activity->vm->AttachCurrentThread(&env, nullptr) != JNI_OK) return;
        attached = true;
    } else if (status != JNI_OK || env == nullptr) {
        return;
    }

    jclass activity_class = env->GetObjectClass(activity->clazz);
    if (activity_class != nullptr && !clear_exception(env)) {
        jmethodID method = env->GetStaticMethodID(activity_class, "requestAccessibilityRefresh", "()V");
        if (method != nullptr && !clear_exception(env)) {
            env->CallStaticVoidMethod(activity_class, method);
            (void)clear_exception(env);
        } else {
            (void)clear_exception(env);
        }
        env->DeleteLocalRef(activity_class);
    } else {
        (void)clear_exception(env);
    }
    if (attached) activity->vm->DetachCurrentThread();
}

}  // namespace

extern "C" {

void elisa_android_accessibility_attach(ANativeActivity *activity) {
    std::lock_guard<std::mutex> lock(state_mutex);
    active_activity = activity;
    if (activity == nullptr) {
        semantic_snapshot.clear();
        action_head = 0;
        action_count = 0;
    }
}

void elisa_android_publish_accessibility(const char *bytes, std::int32_t length) {
    if (bytes == nullptr || length < static_cast<std::int32_t>(kHeaderBytes) ||
        length > static_cast<std::int32_t>(kSnapshotCapacity)) return;
    ANativeActivity *activity = nullptr;
    bool changed = false;
    {
        std::lock_guard<std::mutex> lock(state_mutex);
        const auto *begin = reinterpret_cast<const std::uint8_t *>(bytes);
        std::uint32_t version = 0;
        std::uint32_t count = 0;
        std::memcpy(&version, begin, sizeof(version));
        std::memcpy(&count, begin + sizeof(version), sizeof(count));
        if (version != 1 || count > kMaxVirtualId ||
            kHeaderBytes + static_cast<std::size_t>(count) * kRecordBytes > static_cast<std::size_t>(length)) return;
        changed = semantic_snapshot.size() != static_cast<std::size_t>(length) ||
                  std::memcmp(semantic_snapshot.data(), begin, static_cast<std::size_t>(length)) != 0;
        if (changed) semantic_snapshot.assign(begin, begin + length);
        activity = active_activity;
    }
    if (changed) notify_java(activity);
}

std::int32_t elisa_android_process_accessibility_actions(void) {
    std::array<Action, kActionCapacity> work{};
    std::size_t count = 0;
    {
        std::lock_guard<std::mutex> lock(state_mutex);
        count = action_count;
        for (std::size_t index = 0; index < count; ++index) {
            work[index] = pending_actions[(action_head + index) % kActionCapacity];
        }
        action_head = (action_head + count) % kActionCapacity;
        action_count = 0;
    }
    std::int32_t accepted = 0;
    for (std::size_t index = 0; index < count; ++index) {
        if (elisa_android_accessibility_action(work[index].id, work[index].kind,
                                              work[index].value) != 0) {
            ++accepted;
        }
    }
    return accepted;
}

JNIEXPORT jbyteArray JNICALL Java_org_elisa_1ui_ElisaCanvasActivity_nativeAccessibilitySnapshot(
        JNIEnv *env, jclass self) {
    (void)self;
    std::vector<std::uint8_t> copy;
    {
        std::lock_guard<std::mutex> lock(state_mutex);
        copy = semantic_snapshot;
    }
    if (copy.empty() || copy.size() > static_cast<std::size_t>(INT32_MAX)) return nullptr;
    jbyteArray result = env->NewByteArray(static_cast<jsize>(copy.size()));
    if (result == nullptr) {
        (void)clear_exception(env);
        return nullptr;
    }
    if (clear_exception(env)) return nullptr;
    env->SetByteArrayRegion(result, 0, static_cast<jsize>(copy.size()),
                            reinterpret_cast<const jbyte *>(copy.data()));
    if (clear_exception(env)) {
        env->DeleteLocalRef(result);
        return nullptr;
    }
    return result;
}

JNIEXPORT jboolean JNICALL Java_org_elisa_1ui_ElisaCanvasActivity_nativeAccessibilityAction(
        JNIEnv *env, jclass self, jint id, jint kind, jfloat value) {
    (void)env;
    (void)self;
    if (id < 0 || static_cast<std::uint32_t>(id) >= kMaxVirtualId || kind < 1 || kind > 7 ||
        !std::isfinite(value)) return JNI_FALSE;
    {
        std::lock_guard<std::mutex> lock(state_mutex);
        if (active_activity == nullptr || action_count == kActionCapacity) return JNI_FALSE;
        const std::size_t tail = (action_head + action_count) % kActionCapacity;
        pending_actions[tail] = Action{static_cast<std::uint32_t>(id), kind, value};
        ++action_count;
    }
    elisa_android_request_frame();
    return JNI_TRUE;
}

}  // extern "C"
