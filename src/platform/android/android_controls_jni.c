// The bridge between Elisa and the Java half of the Android controls backend.
//
// Every function here is a call across JNI and nothing else: the class and its
// methods are looked up once, and each entry point marshals its arguments and
// invokes one static method. No decision is taken on this side, because every
// decision was already taken in Elisa -- which control a widget becomes, where
// it sits, which of its colours may cross, and what an action means.
//
// The thread is not a question. Elisa is entered from the Activity's own
// callbacks and from a control's listener, both of which run on Android's UI
// thread, so the environment this needs is always the one already attached.

#include <jni.h>
#include <stddef.h>
#include <stdint.h>
#include "../common/utf8_utf16.h"
#include <string.h>

#define ELISA_CONTROLS_TEXT_MAX 1024

extern int32_t elisa_android_controls_start(float width, float height);
extern void elisa_android_controls_resize(float width, float height);
extern void elisa_android_controls_stop(void);
extern void elisa_android_controls_event(int32_t handle, int32_t event, float value, int32_t selected);
extern void elisa_android_controls_text(int32_t handle, const char *text, int32_t length);

static JavaVM *elisa_vm = NULL;
static jclass elisa_controls_class = NULL;
static jmethodID m_create, m_add_child, m_set_frame, m_set_text, m_set_text_color;
static jmethodID m_set_background_color, m_set_tint_color, m_set_track_color;
static jmethodID m_set_state, m_set_action, m_release_all, m_attach_root;
static jmethodID m_measure_text, m_line_height, m_minimum_height;
static jmethodID m_is_focused, m_caret, m_focus;
static jmethodID m_release, m_set_help;

static JNIEnv *elisa_env(void) {
    JNIEnv *env = NULL;
    if (elisa_vm == NULL) return NULL;
    if ((*elisa_vm)->GetEnv(elisa_vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) return NULL;
    return env;
}

// A Java exception is sticky on a JNIEnv. Leaving one behind turns a
// recoverable control failure into a CheckJNI abort at an unrelated later
// call, so every boundary entry consumes it before returning to Elisa.
static int elisa_controls_clear_exception(JNIEnv *env) {
    if (env == NULL || (*env)->ExceptionCheck(env) != JNI_TRUE) return 0;
    (*env)->ExceptionClear(env);
    return 1;
}

static int elisa_controls_ready(JNIEnv *env) {
    return env != NULL && elisa_controls_class != NULL;
}

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
    (void)reserved;
    elisa_vm = vm;
    JNIEnv *env = elisa_env();
    if (env == NULL) return JNI_ERR;
    jclass local = (*env)->FindClass(env, "org/elisa_ui/ElisaControls");
    if (local == NULL) {
        elisa_controls_clear_exception(env);
        return JNI_ERR;
    }
    // A class reference from FindClass is local and dies with the call that
    // made it; the one this keeps has to outlive every one of them.
    elisa_controls_class = (jclass)(*env)->NewGlobalRef(env, local);
    if (elisa_controls_class == NULL) {
        elisa_controls_clear_exception(env);
        (*env)->DeleteLocalRef(env, local);
        return JNI_ERR;
    }
    jclass c = elisa_controls_class;
    m_create = (*env)->GetStaticMethodID(env, c, "create", "(II)I");
    m_add_child = (*env)->GetStaticMethodID(env, c, "addChild", "(II)V");
    m_set_frame = (*env)->GetStaticMethodID(env, c, "setFrame", "(IFFFF)V");
    m_set_text = (*env)->GetStaticMethodID(env, c, "setText", "(ILjava/lang/String;)V");
    m_set_text_color = (*env)->GetStaticMethodID(env, c, "setTextColor", "(II)V");
    m_set_background_color = (*env)->GetStaticMethodID(env, c, "setBackgroundColor", "(II)V");
    m_set_tint_color = (*env)->GetStaticMethodID(env, c, "setTintColor", "(II)V");
    m_set_track_color = (*env)->GetStaticMethodID(env, c, "setTrackColor", "(II)V");
    m_set_state = (*env)->GetStaticMethodID(env, c, "setState", "(IFZZZ)V");
    m_set_help = (*env)->GetStaticMethodID(env, c, "setHelp", "(ILjava/lang/String;Ljava/lang/String;)V");
    m_set_action = (*env)->GetStaticMethodID(env, c, "setAction", "(I)V");
    m_release_all = (*env)->GetStaticMethodID(env, c, "releaseAll", "()V");
    m_attach_root = (*env)->GetStaticMethodID(env, c, "attachRoot", "(I)V");
    m_measure_text = (*env)->GetStaticMethodID(env, c, "measureTextWidth", "(Ljava/lang/String;FZ)F");
    m_line_height = (*env)->GetStaticMethodID(env, c, "textLineHeight", "(F)F");
    m_minimum_height = (*env)->GetStaticMethodID(env, c, "minimumHeight", "(I)F");
    m_is_focused = (*env)->GetStaticMethodID(env, c, "isFocused", "(I)Z");
    m_caret = (*env)->GetStaticMethodID(env, c, "caret", "(I)I");
    m_focus = (*env)->GetStaticMethodID(env, c, "focus", "(II)V");
    m_release = (*env)->GetStaticMethodID(env, c, "release", "(I)V");
    // A missing method otherwise leaves a null jmethodID behind. JNI does not
    // turn that into a recoverable call failure: the first CallStatic* is a
    // VM abort. Fail library loading while the error is still diagnosable,
    // and release both references acquired during this initialization.
    const int methods_ready =
        m_create != NULL && m_add_child != NULL && m_set_frame != NULL && m_set_text != NULL &&
        m_set_text_color != NULL && m_set_background_color != NULL && m_set_tint_color != NULL &&
        m_set_track_color != NULL && m_set_state != NULL && m_set_help != NULL &&
        m_set_action != NULL && m_release_all != NULL && m_attach_root != NULL &&
        m_measure_text != NULL && m_line_height != NULL && m_minimum_height != NULL &&
        m_is_focused != NULL && m_caret != NULL && m_focus != NULL && m_release != NULL;
    if (!methods_ready || (*env)->ExceptionCheck(env) == JNI_TRUE) {
        if ((*env)->ExceptionCheck(env) == JNI_TRUE) (*env)->ExceptionClear(env);
        (*env)->DeleteGlobalRef(env, elisa_controls_class);
        elisa_controls_class = NULL;
        (*env)->DeleteLocalRef(env, local);
        return JNI_ERR;
    }
    (*env)->DeleteLocalRef(env, local);
    return JNI_VERSION_1_6;
}

// --- Java calling Elisa -------------------------------------------------

JNIEXPORT void JNICALL Java_org_elisa_1ui_ElisaControlsActivity_nativeStart(
        JNIEnv *env, jobject self, jfloat width, jfloat height) {
    (void)env; (void)self;
    elisa_android_controls_start(width, height);
}

JNIEXPORT void JNICALL Java_org_elisa_1ui_ElisaControlsActivity_nativeResize(
        JNIEnv *env, jobject self, jfloat width, jfloat height) {
    (void)env; (void)self;
    elisa_android_controls_resize(width, height);
}

JNIEXPORT void JNICALL Java_org_elisa_1ui_ElisaControlsActivity_nativeStop(
        JNIEnv *env, jobject self) {
    (void)env; (void)self;
    elisa_android_controls_stop();
}

JNIEXPORT void JNICALL Java_org_elisa_1ui_ElisaControls_nativeControlEvent(
        JNIEnv *env, jclass self, jint handle, jint event, jfloat value, jboolean selected) {
    (void)env; (void)self;
    elisa_android_controls_event(handle, event, value, selected == JNI_TRUE ? 1 : 0);
}

// Java strings are UTF-16; the retained layer owns standard UTF-8. Keep the
// conversion at this boundary and pass a counted byte view, including NUL.
JNIEXPORT void JNICALL Java_org_elisa_1ui_ElisaControls_nativeControlText(
        JNIEnv *env, jclass self, jint handle, jstring text) {
    (void)self;
    if (env == NULL) return;
    if (text == NULL) {
        elisa_android_controls_text(handle, "", 0);
        return;
    }
    jsize units_length = (*env)->GetStringLength(env, text);
    if (elisa_controls_clear_exception(env)) return;
    const jchar *units = (*env)->GetStringChars(env, text, NULL);
    if (units == NULL) {
        (void)elisa_controls_clear_exception(env);
        return;
    }
    if (elisa_controls_clear_exception(env)) return;
    uint8_t utf8[ELISA_CONTROLS_TEXT_MAX];
    size_t length = elisa_utf16_to_utf8((const uint16_t *)units,
                                        (size_t)units_length, utf8, sizeof(utf8));
    elisa_android_controls_text(handle, (const char *)utf8, (int32_t)length);
    elisa_secure_clear(utf8, sizeof(utf8));
    (*env)->ReleaseStringChars(env, text, units);
}

// --- Elisa calling Java -------------------------------------------------

int32_t elisa_android_controls_create(int32_t kind, int32_t vertical) {
    JNIEnv *env = elisa_env();
    if (!elisa_controls_ready(env)) return 0;
    jint handle = (*env)->CallStaticIntMethod(env, elisa_controls_class, m_create, kind, vertical);
    return elisa_controls_clear_exception(env) ? 0 : (int32_t)handle;
}

void elisa_android_controls_add_child(int32_t parent, int32_t child) {
    JNIEnv *env = elisa_env();
    if (!elisa_controls_ready(env)) return;
    (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_add_child, parent, child);
    (void)elisa_controls_clear_exception(env);
}

void elisa_android_controls_set_frame(int32_t handle, float x, float y, float width, float height) {
    JNIEnv *env = elisa_env();
    if (!elisa_controls_ready(env)) return;
    (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_set_frame, handle, x, y, width, height);
    (void)elisa_controls_clear_exception(env);
}

// A counted standard UTF-8 view becomes a bounded Java UTF-16 String. NewString
// takes an explicit code-unit length, so embedded U+0000 is preserved.
static jstring elisa_controls_string_from_utf8(JNIEnv *env, const uint8_t *bytes, size_t length) {
    if (env == NULL || (bytes == NULL && length != 0)) return NULL;
    uint16_t units[ELISA_CONTROLS_TEXT_MAX];
    size_t count = elisa_utf8_to_utf16(bytes, length, units,
                                       sizeof(units) / sizeof(units[0]));
    jstring text = (*env)->NewString(env, (const jchar *)units, (jsize)count);
    memset(units, 0, sizeof(units));
    if (text == NULL) {
        (void)elisa_controls_clear_exception(env);
        return NULL;
    }
    if (elisa_controls_clear_exception(env)) return NULL;
    return text;
}

void elisa_android_controls_set_text(int32_t handle, const uint8_t *bytes, size_t length) {
    JNIEnv *env = elisa_env();
    if (env == NULL) return;
    jstring text = elisa_controls_string_from_utf8(env, bytes, length);
    if (text == NULL) return;
    (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_set_text, handle, text);
    (void)elisa_controls_clear_exception(env);
    (*env)->DeleteLocalRef(env, text);
}

void elisa_android_controls_set_text_color(int32_t handle, uint32_t argb) {
    JNIEnv *env = elisa_env();
    if (!elisa_controls_ready(env)) return;
    (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_set_text_color, handle, (jint)argb);
    (void)elisa_controls_clear_exception(env);
}

void elisa_android_controls_set_background_color(int32_t handle, uint32_t argb) {
    JNIEnv *env = elisa_env();
    if (!elisa_controls_ready(env)) return;
    (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_set_background_color, handle, (jint)argb);
    (void)elisa_controls_clear_exception(env);
}

void elisa_android_controls_set_tint_color(int32_t handle, uint32_t argb) {
    JNIEnv *env = elisa_env();
    if (!elisa_controls_ready(env)) return;
    (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_set_tint_color, handle, (jint)argb);
    (void)elisa_controls_clear_exception(env);
}

void elisa_android_controls_set_track_color(int32_t handle, uint32_t argb) {
    JNIEnv *env = elisa_env();
    if (!elisa_controls_ready(env)) return;
    (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_set_track_color, handle, (jint)argb);
    (void)elisa_controls_clear_exception(env);
}

void elisa_android_controls_set_state(int32_t handle, float value, int32_t selected,
                                      int32_t enabled, int32_t secure) {
    JNIEnv *env = elisa_env();
    if (!elisa_controls_ready(env)) return;
    (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_set_state, handle, value,
                                 selected != 0 ? JNI_TRUE : JNI_FALSE,
                                 enabled != 0 ? JNI_TRUE : JNI_FALSE,
                                 secure != 0 ? JNI_TRUE : JNI_FALSE);
    (void)elisa_controls_clear_exception(env);
}

// Two short strings across in one call, each bounded the same way a caption is.
void elisa_android_controls_set_help(int32_t handle, const uint8_t *prompt, size_t prompt_length,
                                     const uint8_t *help, size_t help_length) {
    JNIEnv *env = elisa_env();
    if (env == NULL) return;
    jstring prompt_text = elisa_controls_string_from_utf8(env, prompt, prompt_length);
    if (prompt_text == NULL) return;
    jstring help_text = elisa_controls_string_from_utf8(env, help, help_length);
    if (help_text == NULL) {
        (*env)->DeleteLocalRef(env, prompt_text);
        return;
    }
    (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_set_help, handle, prompt_text, help_text);
    (void)elisa_controls_clear_exception(env);
    (*env)->DeleteLocalRef(env, prompt_text);
    (*env)->DeleteLocalRef(env, help_text);
}

void elisa_android_controls_set_action(int32_t handle) {
    JNIEnv *env = elisa_env();
    if (!elisa_controls_ready(env)) return;
    (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_set_action, handle);
    (void)elisa_controls_clear_exception(env);
}

void elisa_android_controls_release_all(void) {
    JNIEnv *env = elisa_env();
    if (!elisa_controls_ready(env)) return;
    (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_release_all);
    (void)elisa_controls_clear_exception(env);
}

void elisa_android_controls_attach_root(int32_t handle) {
    JNIEnv *env = elisa_env();
    if (!elisa_controls_ready(env)) return;
    (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_attach_root, handle);
    (void)elisa_controls_clear_exception(env);
}

// --- What the platform wants ------------------------------------------
//
// Asked before the layout runs and answered by Android itself, in points.
// The framework has no other way to know how big a native control is, and
// guessing is how it hands one a box it cannot fit its own words into.

float elisa_android_controls_measure_text(const uint8_t *bytes, size_t length, float size, int32_t weighted) {
    JNIEnv *env = elisa_env();
    if (!elisa_controls_ready(env)) return 0.0f;
    jstring text = elisa_controls_string_from_utf8(env, bytes, length);
    if (text == NULL) return 0.0f;
    jfloat width = (*env)->CallStaticFloatMethod(env, elisa_controls_class, m_measure_text, text, size,
                                                 weighted != 0 ? JNI_TRUE : JNI_FALSE);
    if (elisa_controls_clear_exception(env)) width = 0.0f;
    (*env)->DeleteLocalRef(env, text);
    return width;
}

float elisa_android_controls_line_height(float size) {
    JNIEnv *env = elisa_env();
    if (!elisa_controls_ready(env)) return size;
    jfloat height = (*env)->CallStaticFloatMethod(env, elisa_controls_class, m_line_height, size);
    return elisa_controls_clear_exception(env) ? size : height;
}

float elisa_android_controls_minimum_height(int32_t kind) {
    JNIEnv *env = elisa_env();
    if (!elisa_controls_ready(env)) return 0.0f;
    jfloat height = (*env)->CallStaticFloatMethod(env, elisa_controls_class, m_minimum_height, kind);
    return elisa_controls_clear_exception(env) ? 0.0f : height;
}

// Focus, across a realization that replaces every view. Elisa decides which
// control should have it back; these only carry the question and the answer.
int32_t elisa_android_controls_is_focused(int32_t handle) {
    JNIEnv *env = elisa_env();
    if (!elisa_controls_ready(env)) return 0;
    jboolean focused = (*env)->CallStaticBooleanMethod(env, elisa_controls_class, m_is_focused, handle);
    return elisa_controls_clear_exception(env) ? 0 : (focused == JNI_TRUE ? 1 : 0);
}

int32_t elisa_android_controls_caret(int32_t handle) {
    JNIEnv *env = elisa_env();
    if (!elisa_controls_ready(env)) return 0;
    jint caret = (*env)->CallStaticIntMethod(env, elisa_controls_class, m_caret, handle);
    return elisa_controls_clear_exception(env) ? 0 : (int32_t)caret;
}

void elisa_android_controls_focus(int32_t handle, int32_t caret) {
    JNIEnv *env = elisa_env();
    if (!elisa_controls_ready(env)) return;
    (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_focus, handle, caret);
    (void)elisa_controls_clear_exception(env);
}

// One control, given back. Reconciliation releases exactly what the new
// realization did not adopt, so this is the ordinary path and release_all is
// only for tearing the whole interface down.
void elisa_android_controls_release(int32_t handle) {
    JNIEnv *env = elisa_env();
    if (!elisa_controls_ready(env)) return;
    (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_release, handle);
    (void)elisa_controls_clear_exception(env);
}
