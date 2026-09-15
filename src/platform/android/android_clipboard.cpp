// THE SYSTEM CLIPBOARD, FROM A NATIVEACTIVITY.
//
// This is the one backend in the framework that draws its own text field and
// had no clipboard at all. Every other canvas backend has one -- AppKit, UIKit,
// SDL3 and the browser -- and the two native-controls backends deliberately do
// not, because a real UITextField or EditText owns its own selection and its
// own paste menu. Here the framework owns the caret, so copy and paste are the
// framework's to provide, and until this file they silently did nothing.
//
// Android's clipboard lives in Java. The canvas APK already carries one Java
// class for IME composition, but the clipboard still reaches the platform the
// way a NativeActivity is meant to -- through JNI, off the activity object the
// OS already handed us -- rather than adding clipboard state to that class.
//
// Every lookup is done per call and released again. A clipboard operation
// happens when a person presses a key, not every frame, so caching class and
// method IDs here would trade a real lifetime hazard (a cached jclass is only
// valid as a global reference, and the activity can be recreated) for a saving
// nobody can measure.

#include <android/native_activity.h>
#include <jni.h>
#include "../common/utf8_utf16.h"
#include <string.h>

namespace {

ANativeActivity *g_activity = nullptr;

// A JNIEnv belongs to a thread. The native activity's own thread is attached
// already; anything else has to ask, and has to detach again or the VM keeps
// the thread alive.
struct ScopedEnv {
    JNIEnv *env = nullptr;
    bool attached = false;

    explicit ScopedEnv(ANativeActivity *activity) {
        if (activity == nullptr || activity->vm == nullptr) return;
        if (activity->vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6) == JNI_OK) return;
        if (activity->vm->AttachCurrentThread(&env, nullptr) == JNI_OK) {
            attached = true;
            return;
        }
        env = nullptr;
    }

    ~ScopedEnv() {
        if (attached && g_activity != nullptr && g_activity->vm != nullptr) {
            g_activity->vm->DetachCurrentThread();
        }
    }

    bool ok() const { return env != nullptr; }
};

// A pending exception poisons every later JNI call in the same way a CheckJNI
// abort does, so it is cleared at each exit rather than carried out of here.
bool failed(JNIEnv *env) {
    if (env->ExceptionCheck() == JNI_FALSE) return false;
    env->ExceptionClear();
    return true;
}

// The ClipboardManager for this activity, as a local reference the caller
// releases. Null when anything along the way is missing, which is what a
// clipboard-less environment looks like rather than a crash.
jobject clipboard_manager(JNIEnv *env, jobject activity) {
    if (env == nullptr || activity == nullptr) return nullptr;
    jclass context_class = env->FindClass("android/content/Context");
    if (context_class == nullptr || failed(env)) return nullptr;
    jfieldID service_field = env->GetStaticFieldID(context_class, "CLIPBOARD_SERVICE", "Ljava/lang/String;");
    if (service_field == nullptr || failed(env)) {
        env->DeleteLocalRef(context_class);
        return nullptr;
    }
    jobject service_name = env->GetStaticObjectField(context_class, service_field);
    env->DeleteLocalRef(context_class);
    if (service_name == nullptr || failed(env)) return nullptr;

    jclass activity_class = env->GetObjectClass(activity);
    if (activity_class == nullptr || failed(env)) {
        env->DeleteLocalRef(service_name);
        return nullptr;
    }
    jmethodID get_service = env->GetMethodID(activity_class, "getSystemService",
                                             "(Ljava/lang/String;)Ljava/lang/Object;");
    jobject manager = nullptr;
    if (get_service != nullptr && !failed(env)) {
        manager = env->CallObjectMethod(activity, get_service, service_name);
        if (failed(env)) manager = nullptr;
    }
    env->DeleteLocalRef(activity_class);
    env->DeleteLocalRef(service_name);
    return manager;
}

}  // namespace

extern "C" {

// The host calls this once it has an activity, and again with null when the
// activity goes away, so a late clipboard call cannot reach a dead object.
void elisa_android_clipboard_attach(ANativeActivity *activity) {
    g_activity = activity;
}

int32_t elisa_android_clipboard_write(const char *utf8, int32_t length) {
    if (g_activity == nullptr || utf8 == nullptr || length < 0) return 0;
    ScopedEnv scoped(g_activity);
    if (!scoped.ok()) return 0;
    JNIEnv *env = scoped.env;

    jobject manager = clipboard_manager(env, g_activity->clazz);
    if (manager == nullptr) return 0;

    // NewString takes counted UTF-16. JNI's UTF helpers use modified UTF-8,
    // which cannot faithfully carry every scalar in the framework's UTF-8.
    uint16_t units[4095];
    size_t unit_count = elisa_utf8_to_utf16(
        reinterpret_cast<const uint8_t *>(utf8), static_cast<size_t>(length),
        units, sizeof(units) / sizeof(units[0]));

    int32_t wrote = 0;
    jstring text = env->NewString(reinterpret_cast<const jchar *>(units), static_cast<jsize>(unit_count));
    if (text != nullptr && !failed(env)) {
        jclass clip_data = env->FindClass("android/content/ClipData");
        if (clip_data != nullptr && !failed(env)) {
            jmethodID new_plain = env->GetStaticMethodID(
                clip_data, "newPlainText",
                "(Ljava/lang/CharSequence;Ljava/lang/CharSequence;)Landroid/content/ClipData;");
            if (new_plain != nullptr && !failed(env)) {
                jobject clip = env->CallStaticObjectMethod(clip_data, new_plain, nullptr, text);
                if (clip != nullptr && !failed(env)) {
                    jclass manager_class = env->GetObjectClass(manager);
                    if (manager_class != nullptr && !failed(env)) {
                        jmethodID set_primary = env->GetMethodID(manager_class, "setPrimaryClip",
                                                                 "(Landroid/content/ClipData;)V");
                        if (set_primary != nullptr && !failed(env)) {
                            env->CallVoidMethod(manager, set_primary, clip);
                            wrote = failed(env) ? 0 : 1;
                        }
                    }
                    if (manager_class != nullptr) env->DeleteLocalRef(manager_class);
                    env->DeleteLocalRef(clip);
                }
            }
            env->DeleteLocalRef(clip_data);
        }
        env->DeleteLocalRef(text);
    }
    // The staged copy held the user's text; do not leave it in this stack frame.
    memset(units, 0, sizeof(units));
    env->DeleteLocalRef(manager);
    return wrote;
}

// Reads the primary clip as plain text. Returns the byte count written, which
// is zero for an empty clipboard and for one holding something that is not
// text -- coerceToText is what turns a URI or an intent into words the way the
// platform's own paste does.
int32_t elisa_android_clipboard_read(char *buffer, int32_t capacity) {
    if (g_activity == nullptr || buffer == nullptr || capacity <= 0) return 0;
    ScopedEnv scoped(g_activity);
    if (!scoped.ok()) return 0;
    JNIEnv *env = scoped.env;

    jobject manager = clipboard_manager(env, g_activity->clazz);
    if (manager == nullptr) return 0;

    int32_t written = 0;
    jclass manager_class = env->GetObjectClass(manager);
    if (manager_class != nullptr && !failed(env)) {
        jmethodID get_primary = env->GetMethodID(manager_class, "getPrimaryClip",
                                                 "()Landroid/content/ClipData;");
        if (get_primary != nullptr && !failed(env)) {
            jobject clip = env->CallObjectMethod(manager, get_primary);
            if (clip != nullptr && !failed(env)) {
                jclass clip_class = env->GetObjectClass(clip);
                if (clip_class != nullptr && !failed(env)) {
                    jmethodID count_items = env->GetMethodID(clip_class, "getItemCount", "()I");
                    if (count_items != nullptr && !failed(env)) {
                        jmethodID item_at = env->GetMethodID(clip_class, "getItemAt",
                                                             "(I)Landroid/content/ClipData$Item;");
                        if (item_at != nullptr && !failed(env)) {
                            jint count = env->CallIntMethod(clip, count_items);
                            if (!failed(env) && count > 0) {
                                jobject item = env->CallObjectMethod(clip, item_at, 0);
                                if (item != nullptr && !failed(env)) {
                                    jclass item_class = env->GetObjectClass(item);
                                    if (item_class != nullptr && !failed(env)) {
                                        jmethodID coerce = env->GetMethodID(
                                            item_class, "coerceToText",
                                            "(Landroid/content/Context;)Ljava/lang/CharSequence;");
                                        if (coerce != nullptr && !failed(env)) {
                                            jobject text = env->CallObjectMethod(item, coerce, g_activity->clazz);
                                            if (text != nullptr && !failed(env)) {
                                                jclass text_class = env->GetObjectClass(text);
                                                if (text_class != nullptr && !failed(env)) {
                                                    jmethodID to_string = env->GetMethodID(
                                                        text_class, "toString", "()Ljava/lang/String;");
                                                    if (to_string != nullptr && !failed(env)) {
                                                        jstring string = static_cast<jstring>(
                                                            env->CallObjectMethod(text, to_string));
                                                        if (string != nullptr && !failed(env)) {
                                                            jsize unit_count = env->GetStringLength(string);
                                                            const jchar *units = env->GetStringChars(string, nullptr);
                                                            if (units != nullptr) {
                                                                written = static_cast<int32_t>(elisa_utf16_to_utf8(
                                                                    reinterpret_cast<const uint16_t *>(units),
                                                                    static_cast<size_t>(unit_count),
                                                                    reinterpret_cast<uint8_t *>(buffer),
                                                                    static_cast<size_t>(capacity)));
                                                                env->ReleaseStringChars(string, units);
                                                            } else {
                                                                failed(env);
                                                            }
                                                            env->DeleteLocalRef(string);
                                                        }
                                                    }
                                                    env->DeleteLocalRef(text_class);
                                                }
                                                env->DeleteLocalRef(text);
                                            }
                                        }
                                        env->DeleteLocalRef(item_class);
                                    }
                                    env->DeleteLocalRef(item);
                                }
                            }
                        }
                    }
                    env->DeleteLocalRef(clip_class);
                }
                env->DeleteLocalRef(clip);
            }
        }
    }
    if (manager_class != nullptr) env->DeleteLocalRef(manager_class);
    env->DeleteLocalRef(manager);
    return written;
}

// Whether there is text to paste. Asked separately because a framework menu
// greys "Paste" out before anyone presses it, and reading the whole clip to
// answer that would put the user's clipboard through this process for nothing.
int32_t elisa_android_clipboard_has_text(void) {
    if (g_activity == nullptr) return 0;
    ScopedEnv scoped(g_activity);
    if (!scoped.ok()) return 0;
    JNIEnv *env = scoped.env;

    jobject manager = clipboard_manager(env, g_activity->clazz);
    if (manager == nullptr) return 0;

    int32_t has = 0;
    jclass manager_class = env->GetObjectClass(manager);
    if (manager_class != nullptr && !failed(env)) {
        jmethodID has_primary = env->GetMethodID(manager_class, "hasPrimaryClip", "()Z");
        if (has_primary != nullptr && !failed(env)) {
            has = env->CallBooleanMethod(manager, has_primary) == JNI_TRUE ? 1 : 0;
            if (failed(env)) has = 0;
        }
    }
    if (manager_class != nullptr) env->DeleteLocalRef(manager_class);
    env->DeleteLocalRef(manager);
    return has;
}

}  // extern "C"
