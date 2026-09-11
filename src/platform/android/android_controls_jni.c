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
#include <string.h>

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

static JNIEnv *elisa_env(void) {
    JNIEnv *env = NULL;
    if (elisa_vm == NULL) return NULL;
    if ((*elisa_vm)->GetEnv(elisa_vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) return NULL;
    return env;
}

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
    (void)reserved;
    elisa_vm = vm;
    JNIEnv *env = elisa_env();
    if (env == NULL) return JNI_ERR;
    jclass local = (*env)->FindClass(env, "org/elisa_ui/ElisaControls");
    if (local == NULL) return JNI_ERR;
    // A class reference from FindClass is local and dies with the call that
    // made it; the one this keeps has to outlive every one of them.
    elisa_controls_class = (jclass)(*env)->NewGlobalRef(env, local);
    if (elisa_controls_class == NULL) return JNI_ERR;
    jclass c = elisa_controls_class;
    m_create = (*env)->GetStaticMethodID(env, c, "create", "(II)I");
    m_add_child = (*env)->GetStaticMethodID(env, c, "addChild", "(II)V");
    m_set_frame = (*env)->GetStaticMethodID(env, c, "setFrame", "(IFFFF)V");
    m_set_text = (*env)->GetStaticMethodID(env, c, "setText", "(ILjava/lang/String;)V");
    m_set_text_color = (*env)->GetStaticMethodID(env, c, "setTextColor", "(II)V");
    m_set_background_color = (*env)->GetStaticMethodID(env, c, "setBackgroundColor", "(II)V");
    m_set_tint_color = (*env)->GetStaticMethodID(env, c, "setTintColor", "(II)V");
    m_set_track_color = (*env)->GetStaticMethodID(env, c, "setTrackColor", "(II)V");
    m_set_state = (*env)->GetStaticMethodID(env, c, "setState", "(IFZ)V");
    m_set_action = (*env)->GetStaticMethodID(env, c, "setAction", "(I)V");
    m_release_all = (*env)->GetStaticMethodID(env, c, "releaseAll", "()V");
    m_attach_root = (*env)->GetStaticMethodID(env, c, "attachRoot", "(I)V");
    m_measure_text = (*env)->GetStaticMethodID(env, c, "measureTextWidth", "(Ljava/lang/String;FZ)F");
    m_line_height = (*env)->GetStaticMethodID(env, c, "textLineHeight", "(F)F");
    m_minimum_height = (*env)->GetStaticMethodID(env, c, "minimumHeight", "(I)F");
    m_is_focused = (*env)->GetStaticMethodID(env, c, "isFocused", "(I)Z");
    m_caret = (*env)->GetStaticMethodID(env, c, "caret", "(I)I");
    m_focus = (*env)->GetStaticMethodID(env, c, "focus", "(II)V");
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

// A field's text takes a channel of its own: the numeric event carries a value
// and a flag, and a string fits in neither. GetStringUTFChars gives modified
// UTF-8, which differs from the real thing only for NUL and for characters
// outside the BMP -- and Elisa validates the UTF-8 before it keeps any of it,
// so a surrogate pair that arrives mangled is clipped at its boundary rather
// than stored. The bytes are released as soon as Elisa has copied them.
JNIEXPORT void JNICALL Java_org_elisa_1ui_ElisaControls_nativeControlText(
        JNIEnv *env, jclass self, jint handle, jstring text) {
    (void)self;
    if (env == NULL) return;
    if (text == NULL) {
        elisa_android_controls_text(handle, "", 0);
        return;
    }
    const char *utf8 = (*env)->GetStringUTFChars(env, text, NULL);
    if (utf8 == NULL) return;
    jsize length = (*env)->GetStringUTFLength(env, text);
    elisa_android_controls_text(handle, utf8, (int32_t)length);
    (*env)->ReleaseStringUTFChars(env, text, utf8);
}

// --- Elisa calling Java -------------------------------------------------

int32_t elisa_android_controls_create(int32_t kind, int32_t vertical) {
    JNIEnv *env = elisa_env();
    if (env == NULL || elisa_controls_class == NULL) return 0;
    return (*env)->CallStaticIntMethod(env, elisa_controls_class, m_create, kind, vertical);
}

void elisa_android_controls_add_child(int32_t parent, int32_t child) {
    JNIEnv *env = elisa_env();
    if (env != NULL) (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_add_child, parent, child);
}

void elisa_android_controls_set_frame(int32_t handle, float x, float y, float width, float height) {
    JNIEnv *env = elisa_env();
    if (env != NULL) (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_set_frame, handle, x, y, width, height);
}

// A caption crosses as bytes and a length, because that is what Elisa owns: a
// counted view into its own storage, never a terminated C string. The copy is
// bounded here rather than trusted, and the Java string is released before the
// call returns so a realization does not leave a reference per control behind.
#define ELISA_CONTROLS_TEXT_MAX 1024

void elisa_android_controls_set_text(int32_t handle, const uint8_t *bytes, size_t length) {
    JNIEnv *env = elisa_env();
    if (env == NULL) return;
    char buffer[ELISA_CONTROLS_TEXT_MAX + 1];
    size_t take = length > ELISA_CONTROLS_TEXT_MAX ? ELISA_CONTROLS_TEXT_MAX : length;
    if (take > 0 && bytes != NULL) memcpy(buffer, bytes, take);
    buffer[take] = '\0';
    jstring text = (*env)->NewStringUTF(env, buffer);
    if (text == NULL) return;
    (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_set_text, handle, text);
    (*env)->DeleteLocalRef(env, text);
}

void elisa_android_controls_set_text_color(int32_t handle, uint32_t argb) {
    JNIEnv *env = elisa_env();
    if (env != NULL) (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_set_text_color, handle, (jint)argb);
}

void elisa_android_controls_set_background_color(int32_t handle, uint32_t argb) {
    JNIEnv *env = elisa_env();
    if (env != NULL) (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_set_background_color, handle, (jint)argb);
}

void elisa_android_controls_set_tint_color(int32_t handle, uint32_t argb) {
    JNIEnv *env = elisa_env();
    if (env != NULL) (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_set_tint_color, handle, (jint)argb);
}

void elisa_android_controls_set_track_color(int32_t handle, uint32_t argb) {
    JNIEnv *env = elisa_env();
    if (env != NULL) (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_set_track_color, handle, (jint)argb);
}

void elisa_android_controls_set_state(int32_t handle, float value, int32_t selected) {
    JNIEnv *env = elisa_env();
    if (env != NULL) (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_set_state, handle, value,
                                                  selected != 0 ? JNI_TRUE : JNI_FALSE);
}

void elisa_android_controls_set_action(int32_t handle) {
    JNIEnv *env = elisa_env();
    if (env != NULL) (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_set_action, handle);
}

void elisa_android_controls_release_all(void) {
    JNIEnv *env = elisa_env();
    if (env != NULL) (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_release_all);
}

void elisa_android_controls_attach_root(int32_t handle) {
    JNIEnv *env = elisa_env();
    if (env != NULL) (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_attach_root, handle);
}

// --- What the platform wants ------------------------------------------
//
// Asked before the layout runs and answered by Android itself, in points.
// The framework has no other way to know how big a native control is, and
// guessing is how it hands one a box it cannot fit its own words into.

float elisa_android_controls_measure_text(const uint8_t *bytes, size_t length, float size, int32_t weighted) {
    JNIEnv *env = elisa_env();
    if (env == NULL) return 0.0f;
    char buffer[ELISA_CONTROLS_TEXT_MAX + 1];
    size_t take = length > ELISA_CONTROLS_TEXT_MAX ? ELISA_CONTROLS_TEXT_MAX : length;
    if (take > 0 && bytes != NULL) memcpy(buffer, bytes, take);
    buffer[take] = '\0';
    jstring text = (*env)->NewStringUTF(env, buffer);
    if (text == NULL) return 0.0f;
    jfloat width = (*env)->CallStaticFloatMethod(env, elisa_controls_class, m_measure_text, text, size,
                                                 weighted != 0 ? JNI_TRUE : JNI_FALSE);
    (*env)->DeleteLocalRef(env, text);
    return width;
}

float elisa_android_controls_line_height(float size) {
    JNIEnv *env = elisa_env();
    if (env == NULL) return size;
    return (*env)->CallStaticFloatMethod(env, elisa_controls_class, m_line_height, size);
}

float elisa_android_controls_minimum_height(int32_t kind) {
    JNIEnv *env = elisa_env();
    if (env == NULL) return 0.0f;
    return (*env)->CallStaticFloatMethod(env, elisa_controls_class, m_minimum_height, kind);
}

// Focus, across a realization that replaces every view. Elisa decides which
// control should have it back; these only carry the question and the answer.
int32_t elisa_android_controls_is_focused(int32_t handle) {
    JNIEnv *env = elisa_env();
    if (env == NULL || elisa_controls_class == NULL) return 0;
    return (*env)->CallStaticBooleanMethod(env, elisa_controls_class, m_is_focused, handle) == JNI_TRUE ? 1 : 0;
}

int32_t elisa_android_controls_caret(int32_t handle) {
    JNIEnv *env = elisa_env();
    if (env == NULL || elisa_controls_class == NULL) return 0;
    return (*env)->CallStaticIntMethod(env, elisa_controls_class, m_caret, handle);
}

void elisa_android_controls_focus(int32_t handle, int32_t caret) {
    JNIEnv *env = elisa_env();
    if (env == NULL || elisa_controls_class == NULL) return;
    (*env)->CallStaticVoidMethod(env, elisa_controls_class, m_focus, handle, caret);
}
