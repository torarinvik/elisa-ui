// Java permission callbacks run on Android's UI thread. Queue their facts so
// the portable service state is only read or changed on android_main.

#include <android/log.h>
#include <android/native_activity.h>
#include <jni.h>

#include <array>
#include <cstdint>
#include <mutex>

extern "C" void elisa_android_request_frame(void);
extern "C" std::int32_t elisa_android_permission_result(std::uint32_t slot,
                                                        std::uint32_t generation,
                                                        std::int32_t state,
                                                        std::int32_t failure);
extern "C" std::int32_t elisa_android_permission_sync(std::int32_t kind,
                                                      std::int32_t state,
                                                      std::int32_t failure);
extern "C" std::int32_t elisa_android_picker_result(std::uint32_t slot,
                                                    std::uint32_t generation,
                                                    std::int32_t state,
                                                    std::uint32_t selection_kind,
                                                    std::uint64_t selection_id);

namespace {

enum class FactKind : std::uint8_t { Prompt, Sync, Picker };

struct ServiceFact {
    FactKind kind;
    std::uint32_t slot;
    std::uint32_t generation;
    std::int32_t service;
    std::int32_t state;
    std::int32_t failure;
    std::uint32_t selection_kind;
    std::uint64_t selection_id;
};

constexpr std::size_t kCapacity = 32;
std::array<ServiceFact, kCapacity> pending{};
std::size_t pending_count = 0;
std::mutex pending_mutex;
ANativeActivity *active_activity = nullptr;

bool push(const ServiceFact &fact) {
    std::lock_guard<std::mutex> lock(pending_mutex);
    if (pending_count == kCapacity) {
        __android_log_print(ANDROID_LOG_ERROR, "elisa-ui", "service callback queue full");
        return false;
    }
    pending[pending_count++] = fact;
    return true;
}

bool clear_exception(JNIEnv *env) {
    if (env == nullptr || !env->ExceptionCheck()) return false;
    env->ExceptionClear();
    return true;
}

}  // namespace

extern "C" void elisa_android_services_attach(ANativeActivity *activity) {
    std::lock_guard<std::mutex> lock(pending_mutex);
    active_activity = activity;
}

extern "C" std::int32_t elisa_android_request_permission(std::int32_t kind,
                                                         std::uint32_t slot,
                                                         std::uint32_t generation) {
    ANativeActivity *activity = nullptr;
    {
        std::lock_guard<std::mutex> lock(pending_mutex);
        activity = active_activity;
    }
    if (activity == nullptr || activity->vm == nullptr || activity->clazz == nullptr) return 0;

    JNIEnv *env = nullptr;
    bool attached = false;
    const jint status = activity->vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6);
    if (status == JNI_EDETACHED) {
        if (activity->vm->AttachCurrentThread(&env, nullptr) != JNI_OK) return 0;
        attached = true;
    } else if (status != JNI_OK || env == nullptr) {
        return 0;
    }

    std::int32_t accepted = 0;
    jclass activity_class = env->GetObjectClass(activity->clazz);
    if (activity_class != nullptr && !clear_exception(env)) {
        jmethodID method = env->GetStaticMethodID(activity_class, "requestPermission", "(III)I");
        if (method != nullptr && !clear_exception(env)) {
            accepted = env->CallStaticIntMethod(activity_class, method, kind,
                                                static_cast<jint>(slot),
                                                static_cast<jint>(generation));
            if (clear_exception(env)) accepted = 0;
        } else {
            (void)clear_exception(env);
        }
        env->DeleteLocalRef(activity_class);
    } else {
        (void)clear_exception(env);
    }
    if (attached) activity->vm->DetachCurrentThread();
    return accepted;
}

extern "C" std::int32_t elisa_android_present_picker(std::int32_t kind,
                                                      std::uint32_t slot,
                                                      std::uint32_t generation) {
    if ((kind != 2 && kind != 5) || slot >= 64 || generation == 0) return 0;
    ANativeActivity *activity = nullptr;
    {
        std::lock_guard<std::mutex> lock(pending_mutex);
        activity = active_activity;
    }
    if (activity == nullptr || activity->vm == nullptr || activity->clazz == nullptr) return 0;
    JNIEnv *env = nullptr;
    bool attached = false;
    const jint status = activity->vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6);
    if (status == JNI_EDETACHED) {
        if (activity->vm->AttachCurrentThread(&env, nullptr) != JNI_OK) return 0;
        attached = true;
    } else if (status != JNI_OK || env == nullptr) {
        return 0;
    }
    std::int32_t accepted = 0;
    jclass activity_class = env->GetObjectClass(activity->clazz);
    if (activity_class != nullptr && !clear_exception(env)) {
        jmethodID method = env->GetStaticMethodID(activity_class, "presentPicker", "(III)I");
        if (method != nullptr && !clear_exception(env)) {
            accepted = env->CallStaticIntMethod(activity_class, method, kind,
                                                static_cast<jint>(slot),
                                                static_cast<jint>(generation));
            if (clear_exception(env)) accepted = 0;
        } else {
            (void)clear_exception(env);
        }
        env->DeleteLocalRef(activity_class);
    } else {
        (void)clear_exception(env);
    }
    if (attached) activity->vm->DetachCurrentThread();
    return accepted;
}

extern "C" std::int32_t elisa_android_read_selection(std::uint64_t selection_id,
                                                      std::uint64_t offset,
                                                      std::uint8_t *buffer,
                                                      std::int32_t capacity) {
    if (selection_id == 0 || selection_id > static_cast<std::uint64_t>(INT64_MAX) ||
        offset > static_cast<std::uint64_t>(INT64_MAX) || capacity < 0 || capacity > 65536 ||
        (capacity > 0 && buffer == nullptr)) return -1;
    ANativeActivity *activity = nullptr;
    {
        std::lock_guard<std::mutex> lock(pending_mutex);
        activity = active_activity;
    }
    if (activity == nullptr || activity->vm == nullptr || activity->clazz == nullptr) return -1;
    JNIEnv *env = nullptr;
    bool attached = false;
    const jint status = activity->vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6);
    if (status == JNI_EDETACHED) {
        if (activity->vm->AttachCurrentThread(&env, nullptr) != JNI_OK) return -1;
        attached = true;
    } else if (status != JNI_OK || env == nullptr) {
        return -1;
    }
    std::int32_t read = -1;
    jclass activity_class = env->GetObjectClass(activity->clazz);
    if (activity_class != nullptr && !clear_exception(env)) {
        jmethodID method = env->GetStaticMethodID(activity_class, "readSelectedBytes", "(JJ[B)I");
        if (method != nullptr && !clear_exception(env)) {
            jbyteArray bytes = env->NewByteArray(capacity);
            if (bytes != nullptr && !clear_exception(env)) {
                read = env->CallStaticIntMethod(activity_class, method,
                                                static_cast<jlong>(selection_id),
                                                static_cast<jlong>(offset), bytes);
                if (clear_exception(env) || read < 0 || read > capacity) {
                    read = -1;
                } else if (read > 0) {
                    env->GetByteArrayRegion(bytes, 0, read, reinterpret_cast<jbyte *>(buffer));
                    if (clear_exception(env)) read = -1;
                }
                env->DeleteLocalRef(bytes);
            } else {
                (void)clear_exception(env);
            }
        } else {
            (void)clear_exception(env);
        }
        env->DeleteLocalRef(activity_class);
    } else {
        (void)clear_exception(env);
    }
    if (attached) activity->vm->DetachCurrentThread();
    return read;
}

extern "C" std::int32_t elisa_android_release_selection(std::uint64_t selection_id) {
    if (selection_id == 0 || selection_id > static_cast<std::uint64_t>(INT64_MAX)) return 0;
    ANativeActivity *activity = nullptr;
    {
        std::lock_guard<std::mutex> lock(pending_mutex);
        activity = active_activity;
    }
    if (activity == nullptr || activity->vm == nullptr || activity->clazz == nullptr) return 0;
    JNIEnv *env = nullptr;
    bool attached = false;
    const jint status = activity->vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6);
    if (status == JNI_EDETACHED) {
        if (activity->vm->AttachCurrentThread(&env, nullptr) != JNI_OK) return 0;
        attached = true;
    } else if (status != JNI_OK || env == nullptr) {
        return 0;
    }
    std::int32_t released = 0;
    jclass activity_class = env->GetObjectClass(activity->clazz);
    if (activity_class != nullptr && !clear_exception(env)) {
        jmethodID method = env->GetStaticMethodID(activity_class, "releaseSelectedBytes", "(J)I");
        if (method != nullptr && !clear_exception(env)) {
            released = env->CallStaticIntMethod(activity_class, method,
                                                static_cast<jlong>(selection_id));
            if (clear_exception(env)) released = 0;
        } else {
            (void)clear_exception(env);
        }
        env->DeleteLocalRef(activity_class);
    } else {
        (void)clear_exception(env);
    }
    if (attached) activity->vm->DetachCurrentThread();
    return released;
}

extern "C" void elisa_android_process_service_results(void) {
    std::array<ServiceFact, kCapacity> ready{};
    std::size_t count = 0;
    {
        std::lock_guard<std::mutex> lock(pending_mutex);
        count = pending_count;
        for (std::size_t index = 0; index < count; ++index) ready[index] = pending[index];
        pending_count = 0;
    }
    for (std::size_t index = 0; index < count; ++index) {
        const ServiceFact &fact = ready[index];
        if (fact.kind == FactKind::Prompt) {
            (void)elisa_android_permission_result(fact.slot, fact.generation,
                                                 fact.state, fact.failure);
        } else if (fact.kind == FactKind::Sync) {
            (void)elisa_android_permission_sync(fact.service, fact.state, fact.failure);
        } else {
            const std::int32_t accepted = elisa_android_picker_result(
                fact.slot, fact.generation, fact.state,
                fact.selection_kind, fact.selection_id);
            if (accepted != 1 && fact.selection_id != 0) {
                (void)elisa_android_release_selection(fact.selection_id);
            }
        }
    }
}

extern "C" void Java_org_elisa_1ui_ElisaCanvasActivity_nativePermissionResult(
        JNIEnv *env, jclass self, jint slot, jint generation, jint state, jint failure) {
    (void)env;
    (void)self;
    if (slot < 0 || generation <= 0) return;
    if (push(ServiceFact{FactKind::Prompt, static_cast<std::uint32_t>(slot),
                         static_cast<std::uint32_t>(generation), 0, state, failure, 0, 0})) {
        elisa_android_request_frame();
    }
}

extern "C" void Java_org_elisa_1ui_ElisaCanvasActivity_nativePermissionSync(
        JNIEnv *env, jclass self, jint service, jint state, jint failure) {
    (void)env;
    (void)self;
    if (service < 0 || service > 1) return;
    if (push(ServiceFact{FactKind::Sync, 0, 0, service, state, failure, 0, 0})) {
        elisa_android_request_frame();
    }
}

extern "C" void Java_org_elisa_1ui_ElisaCanvasActivity_nativePickerResult(
        JNIEnv *env, jclass self, jint slot, jint generation, jint state,
        jint selection_kind, jlong selection_id) {
    (void)env;
    (void)self;
    if (slot < 0 || slot >= 64 || generation <= 0) {
        if (selection_id > 0) (void)elisa_android_release_selection(
            static_cast<std::uint64_t>(selection_id));
        return;
    }
    if (state == 2) {
        if (selection_id <= 0 || selection_kind < 1 || selection_kind > 6) {
            if (selection_id > 0) (void)elisa_android_release_selection(
                static_cast<std::uint64_t>(selection_id));
            return;
        }
    } else if ((state != 3 && state != 4 && state != 5) || selection_id != 0 || selection_kind != 0) {
        if (selection_id > 0) (void)elisa_android_release_selection(
            static_cast<std::uint64_t>(selection_id));
        return;
    }
    if (push(ServiceFact{FactKind::Picker, static_cast<std::uint32_t>(slot),
                         static_cast<std::uint32_t>(generation), 0, state, 0,
                         static_cast<std::uint32_t>(selection_kind),
                         static_cast<std::uint64_t>(selection_id)})) {
        elisa_android_request_frame();
    } else if (selection_id > 0) {
        (void)elisa_android_release_selection(static_cast<std::uint64_t>(selection_id));
    }
}
