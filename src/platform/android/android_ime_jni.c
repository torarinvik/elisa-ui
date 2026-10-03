// The IME crossing for the painted backend.
//
// JNI converts and queues connection-owned edits. Only the native looper
// invokes retained editing; Elisa resolves composition and cursor semantics.

#include <android/log.h>
#include <android/native_activity.h>
#include <jni.h>
#include <stdint.h>
#include <string.h>
#include "../common/utf8_utf16.h"
#include "android_ime_transport.inc"

#define ELISA_IME_TEXT_MAX 1024
extern void elisa_android_request_frame(void);

JNIEXPORT jboolean JNICALL Java_org_elisa_1ui_ElisaCanvasActivity_nativeImeAction(
        JNIEnv *env, jclass self, jlong owner, jint action) {
    (void)env; (void)self;
    int accepted = elisa_ime_queue_push(&elisa_ime_commands, (uint64_t)owner, 10, action, NULL, 0);
    if (accepted) elisa_android_request_frame();
    return accepted ? JNI_TRUE : JNI_FALSE;
}

// READING BACK, for the gate. Composition is the one thing on this backend
// that no display could show and no frame count could catch: a composing run
// that never arrived and one that arrived twice draw the same number of
// colours. So the framework is asked what it holds, and the answer goes to
// the same log the frame trace uses.
extern const char *elisa_android_ime_text(void);
extern int32_t elisa_android_ime_marked_units(void);
extern int32_t elisa_android_ime_cursor_from_mark(void);
extern int32_t elisa_android_text_purpose(void);
extern int32_t elisa_android_keyboard_insets(float bottom, int32_t visible);
extern void elisa_android_request_frame(void);
extern void elisa_android_request_back(void);

static float elisa_ime_last_inset_bottom = -1.0f;
JNIEXPORT jlongArray JNICALL Java_org_elisa_1ui_ElisaCanvasActivity_nativeImeConnection(JNIEnv *env, jclass self) {
    (void)self;
    elisa_ime_snapshot snapshot = elisa_ime_connection_snapshot();
    jlong values[7] = {(jlong)snapshot.owner, (jlong)snapshot.purpose, snapshot.start, snapshot.end, snapshot.mark_start, snapshot.mark_end, (jlong)snapshot.menu_serial};
    jlongArray result = (*env)->NewLongArray(env, 7);
    if (result != NULL) (*env)->SetLongArrayRegion(env, result, 0, 7, values);
    return result;
}
JNIEXPORT jstring JNICALL Java_org_elisa_1ui_ElisaCanvasActivity_nativeImeReadback(
        JNIEnv *env, jclass self, jlong owner, jint mode, jint count) {
    (void)self;
    uint16_t units[ELISA_IME_QUEUE_BYTES];
    int32_t length = elisa_ime_readback((uint64_t)owner, mode, count, units);
    jstring result = length < 0 ? NULL : (*env)->NewString(env, (const jchar *)units, length);
    elisa_secure_clear(units, sizeof(units));
    return result;
}
static int32_t elisa_ime_last_inset_visible = -1;
JNIEXPORT jobjectArray JNICALL Java_org_elisa_1ui_ElisaCanvasActivity_nativeImeDocument(
        JNIEnv *env, jclass self, jlong owner) {
    (void)self;
    uint16_t units[ELISA_IME_QUEUE_BYTES];
    int32_t positions[2];
    int32_t length = elisa_ime_document((uint64_t)owner, units, positions);
    if (length < 0) { elisa_secure_clear(units, sizeof(units)); return NULL; }
    jstring text = (*env)->NewString(env, (const jchar *)units, length);
    elisa_secure_clear(units, sizeof(units));
    if (text == NULL) return NULL;
    jintArray selection = (*env)->NewIntArray(env, 2);
    if (selection == NULL) { (*env)->DeleteLocalRef(env, text); return NULL; }
    jint endpoints[2] = {positions[0], positions[1]};
    (*env)->SetIntArrayRegion(env, selection, 0, 2, endpoints);
    if ((*env)->ExceptionCheck(env)) {
        (*env)->DeleteLocalRef(env, text);
        (*env)->DeleteLocalRef(env, selection);
        return NULL;
    }
    jclass object_class = (*env)->FindClass(env, "java/lang/Object");
    jobjectArray result = object_class == NULL ? NULL : (*env)->NewObjectArray(env, 2, object_class, NULL);
    if (result != NULL) {
        (*env)->SetObjectArrayElement(env, result, 0, text);
        (*env)->SetObjectArrayElement(env, result, 1, selection);
    }
    if (object_class != NULL) (*env)->DeleteLocalRef(env, object_class);
    (*env)->DeleteLocalRef(env, text);
    (*env)->DeleteLocalRef(env, selection);
    return result;
}
static int elisa_ime_failed(JNIEnv *env);

static int elisa_ime_call_activity(ANativeActivity *activity, const char *method_name) {
    if (activity == NULL || activity->vm == NULL || activity->clazz == NULL) return 0;
    JavaVM *vm = activity->vm;
    JNIEnv *env = NULL;
    int attached = 0;
    jint state = (*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6);
    if (state == JNI_EDETACHED) {
        if ((*vm)->AttachCurrentThread(vm, &env, NULL) != JNI_OK) return 0;
        attached = 1;
    } else if (state != JNI_OK || env == NULL) {
        return 0;
    }

    int called = 0;
    jclass activity_class = (*env)->GetObjectClass(env, activity->clazz);
    if (activity_class != NULL && !elisa_ime_failed(env)) {
        jmethodID method = (*env)->GetStaticMethodID(env, activity_class, method_name, "()V");
        if (method != NULL && !elisa_ime_failed(env)) {
            (*env)->CallStaticVoidMethod(env, activity_class, method);
            called = !elisa_ime_failed(env);
        }
        (*env)->DeleteLocalRef(env, activity_class);
    } else {
        (void)elisa_ime_failed(env);
    }
    if (attached) (*vm)->DetachCurrentThread(vm);
    return called;
}

static int elisa_ime_failed(JNIEnv *env) {
    if (env == NULL || (*env)->ExceptionCheck(env) == JNI_FALSE) return 0;
    (*env)->ExceptionClear(env);
    return 1;
}

void elisa_android_ime_show_keyboard(ANativeActivity *activity) {
    if (!elisa_ime_call_activity(activity, "requestImeShow")) {
        __android_log_print(ANDROID_LOG_WARN, "elisa-ui", "ime show request failed");
    }
}

void elisa_android_ime_hide_keyboard(ANativeActivity *activity) {
    if (!elisa_ime_call_activity(activity, "requestImeHide")) {
        __android_log_print(ANDROID_LOG_WARN, "elisa-ui", "ime hide request failed");
    }
}

void elisa_android_ime_update_selection(ANativeActivity *activity) {
    (void)elisa_ime_call_activity(activity, "requestImeSelection");
}

void elisa_android_activity_unhandled_back(ANativeActivity *activity) {
    if (!elisa_ime_call_activity(activity, "requestUnhandledBack")) {
        __android_log_print(ANDROID_LOG_WARN, "elisa-ui", "unhandled back request failed");
    }
}

JNIEXPORT void JNICALL Java_org_elisa_1ui_ElisaCanvasActivity_nativeBack(
        JNIEnv *env, jclass self) {
    (void)env; (void)self;
    elisa_android_request_back();
}

// Java strings are UTF-16; the retained text API takes standard UTF-8. Convert
// here, while preserving the IME's selection offsets in their native UTF-16 unit.
static jboolean elisa_ime_forward(JNIEnv *env, uint64_t owner, jstring text, int32_t new_cursor_position,
                              int composing) {
    if (env == NULL || owner == 0) return JNI_FALSE;
    if (text == NULL) {
        int accepted = elisa_ime_queue_push(&elisa_ime_commands, owner,
                composing ? 0 : 1, new_cursor_position, NULL, 0);
        if (accepted) elisa_android_request_frame();
        return accepted ? JNI_TRUE : JNI_FALSE;
    }
    jsize units_length = (*env)->GetStringLength(env, text);
    if (elisa_ime_failed(env) || units_length > ELISA_IME_TEXT_MAX) return JNI_FALSE;
    const jchar *units = (*env)->GetStringChars(env, text, NULL);
    if (units == NULL) {
        (void)elisa_ime_failed(env);
        return JNI_FALSE;
    }
    if (elisa_ime_failed(env)) {
        (*env)->ReleaseStringChars(env, text, units);
        return JNI_FALSE;
    }
    int accepted = elisa_ime_enqueue_utf16(owner, composing ? 0 : 1,
            new_cursor_position, (const uint16_t *)units, (size_t)units_length);
    (*env)->ReleaseStringChars(env, text, units);
    if (accepted) elisa_android_request_frame();
    return accepted ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL Java_org_elisa_1ui_ElisaCanvasActivity_nativeComposingText(
        JNIEnv *env, jclass self, jlong owner, jstring text, jint new_cursor_position) {
    (void)self;
    return elisa_ime_forward(env, (uint64_t)owner, text, (int32_t)new_cursor_position, 1);
}

JNIEXPORT jboolean JNICALL Java_org_elisa_1ui_ElisaCanvasActivity_nativeFinishComposing(
        JNIEnv *env, jclass self, jlong owner) {
    (void)env; (void)self;
    int accepted = elisa_ime_queue_push(&elisa_ime_commands, (uint64_t)owner, 3, 0, NULL, 0);
    if (accepted) elisa_android_request_frame();
    return accepted ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL Java_org_elisa_1ui_ElisaCanvasActivity_nativeImeBatch(
        JNIEnv *env, jclass self, jlong owner, jint phase) {
    (void)env; (void)self;
    if (phase < 0 || phase > 2) return JNI_FALSE;
    int accepted = elisa_ime_queue_push(&elisa_ime_commands, (uint64_t)owner,
            phase == 0 ? 8 : 9, phase == 2 ? 1 : 0, NULL, 0);
    if (accepted) elisa_android_request_frame();
    return accepted ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL Java_org_elisa_1ui_ElisaCanvasActivity_nativeSelection(
        JNIEnv *env, jclass self, jlong owner, jint start, jint stop, jboolean composing) {
    (void)env; (void)self;
    if (composing != JNI_TRUE && (start < 0 || stop < 0)) return JNI_FALSE;
    int32_t end = (int32_t)stop;
    int accepted = elisa_ime_queue_push(&elisa_ime_commands, (uint64_t)owner,
            composing == JNI_TRUE ? 7 : 4, (int32_t)start, &end, sizeof(end));
    if (accepted) elisa_android_request_frame();
    return accepted ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL Java_org_elisa_1ui_ElisaCanvasActivity_nativeDeleteSurrounding(
        JNIEnv *env, jclass self, jlong owner, jint before, jint after, jboolean codepoints) {
    (void)env; (void)self;
    if (before < 0 || after < 0) return JNI_FALSE;
    int32_t following = (int32_t)after;
    int accepted = elisa_ime_queue_push(&elisa_ime_commands, (uint64_t)owner,
            codepoints == JNI_TRUE ? 6 : 5, (int32_t)before, &following, sizeof(following));
    if (accepted) elisa_android_request_frame();
    return accepted ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL Java_org_elisa_1ui_ElisaCanvasActivity_nativeCommitText(
        JNIEnv *env, jclass self, jlong owner, jstring text, jint new_cursor_position) {
    (void)self;
    return elisa_ime_forward(env, (uint64_t)owner, text, (int32_t)new_cursor_position, 0);
}

// The probe's three questions. None of them is a test double: the text and the
// composing length come from the framework's own accessors, the same ones the
// painted field draws itself from.
JNIEXPORT jint JNICALL Java_org_elisa_1ui_ElisaCanvasActivity_nativeImeReady(
        JNIEnv *env, jclass self) {
    (void)env; (void)self;
    elisa_ime_snapshot snapshot = elisa_ime_connection_snapshot();
    return snapshot.owner != 0 && snapshot.purpose >= 0 ? 1 : 0;
}

JNIEXPORT void JNICALL Java_org_elisa_1ui_ElisaCanvasActivity_nativeImeReport(
        JNIEnv *env, jclass self, jstring tag) {
    (void)self;
    uint8_t label[128];
    size_t label_length = 0;
    const jchar *tag_units = NULL;
    if (tag != NULL && env != NULL) {
        jsize tag_length = (*env)->GetStringLength(env, tag);
        if (!elisa_ime_failed(env)) {
            tag_units = (*env)->GetStringChars(env, tag, NULL);
            if (tag_units == NULL) {
                (void)elisa_ime_failed(env);
            } else if (!elisa_ime_failed(env)) {
                label_length = elisa_utf16_to_utf8((const uint16_t *)tag_units,
                                                   (size_t)tag_length, label,
                                                   sizeof(label) - 1);
            }
        }
    }
    if (tag_units == NULL) {
        label[0] = '?';
        label_length = 1;
    }
    label[label_length] = 0;
    int accepted = elisa_ime_queue_push(&elisa_ime_commands,
            elisa_ime_connection_owner(), 2, 0, label, label_length);
    if (tag_units != NULL) (*env)->ReleaseStringChars(env, tag, tag_units);
    if (accepted) elisa_android_request_frame();
    else __android_log_print(ANDROID_LOG_WARN, "elisa-ui", "ime report rejected tag=%s", (const char *)label);
    elisa_secure_clear(label, sizeof(label));
}

// Ordered with edits and evaluated exclusively on the retained owner thread.
static void elisa_ime_deliver_report(const char *label) {
    int32_t purpose = elisa_android_text_purpose();
    if (purpose == 1 || purpose < 0 || purpose > 5) {
        __android_log_print(ANDROID_LOG_INFO, "elisa-ui", "ime %s secure=redacted", label);
        return;
    }
    const char *value = elisa_android_ime_text();
    __android_log_print(ANDROID_LOG_INFO, "elisa-ui", "ime %s text=[%s] marked=%d cursor=%d",
                        (const char *)label,
                        value == NULL ? "" : value, (int)elisa_android_ime_marked_units(),
                        (int)elisa_android_ime_cursor_from_mark());
}

static void elisa_ime_deliver_insets(float logical_bottom, int32_t shown) {
    const int32_t accepted = elisa_android_keyboard_insets(logical_bottom, shown);
    if (shown != elisa_ime_last_inset_visible || logical_bottom != elisa_ime_last_inset_bottom || !accepted) {
        __android_log_print(ANDROID_LOG_INFO, "elisa-ui",
                            "ime-insets bottom=%.2f visible=%d accepted=%d",
                            logical_bottom, (int)shown, (int)accepted);
        elisa_ime_last_inset_bottom = logical_bottom;
        elisa_ime_last_inset_visible = shown;
    }
}

JNIEXPORT void JNICALL Java_org_elisa_1ui_ElisaCanvasActivity_nativeKeyboardInsets(
        JNIEnv *env, jclass self, jfloat bottom, jboolean visible) {
    (void)env; (void)self;
    if (elisa_ime_enqueue_insets(bottom, visible == JNI_TRUE ? 1 : 0))
        elisa_android_request_frame();
}
