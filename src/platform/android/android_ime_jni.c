// The IME crossing for the painted backend.
//
// One JNI entry per thing the input connection reports, and neither decides
// anything: Elisa already knows how to place a composing run, how to replace
// the previous one and where the caret goes, because the two Apple canvases
// have driven exactly that API for as long as they have existed.

#include <android/log.h>
#include <jni.h>
#include <stdint.h>
#include <string.h>

#define ELISA_IME_TEXT_MAX 1024

extern void elisa_android_composing_text(const char *text, int32_t length,
                                         int32_t selection_start, int32_t selection_length);
extern void elisa_android_commit_text(const char *text, int32_t length);

// READING BACK, for the gate. Composition is the one thing on this backend
// that no display could show and no frame count could catch: a composing run
// that never arrived and one that arrived twice draw the same number of
// colours. So the framework is asked what it holds, and the answer goes to
// the same log the frame trace uses.
extern const char *elisa_android_ime_text(void);
extern int32_t elisa_android_ime_marked_units(void);
extern int32_t elisa_android_wants_keyboard(void);

// GetStringUTFChars gives modified UTF-8, which differs from the real thing
// only for NUL and for characters outside the BMP. Elisa validates the encoding
// before keeping any of it, so a mangled surrogate pair is clipped at its
// boundary rather than stored -- the same contract the control backend's text
// channel has.
static void elisa_ime_forward(JNIEnv *env, jstring text, int32_t selection_start,
                              int32_t selection_length, int composing) {
    if (env == NULL) return;
    if (text == NULL) {
        if (composing) elisa_android_composing_text("", 0, 0, 0);
        else elisa_android_commit_text("", 0);
        return;
    }
    const char *utf8 = (*env)->GetStringUTFChars(env, text, NULL);
    if (utf8 == NULL) return;
    jsize length = (*env)->GetStringUTFLength(env, text);
    if (length > ELISA_IME_TEXT_MAX) length = ELISA_IME_TEXT_MAX;
    if (composing) elisa_android_composing_text(utf8, (int32_t)length, selection_start, selection_length);
    else elisa_android_commit_text(utf8, (int32_t)length);
    (*env)->ReleaseStringUTFChars(env, text, utf8);
}

JNIEXPORT void JNICALL Java_org_elisa_1ui_ElisaCanvasActivity_nativeComposingText(
        JNIEnv *env, jclass self, jstring text, jint selection_start, jint selection_length) {
    (void)self;
    elisa_ime_forward(env, text, (int32_t)selection_start, (int32_t)selection_length, 1);
}

JNIEXPORT void JNICALL Java_org_elisa_1ui_ElisaCanvasActivity_nativeCommitText(
        JNIEnv *env, jclass self, jstring text) {
    (void)self;
    elisa_ime_forward(env, text, 0, 0, 0);
}

// The probe's three questions. None of them is a test double: the text and the
// composing length come from the framework's own accessors, the same ones the
// painted field draws itself from.
JNIEXPORT jint JNICALL Java_org_elisa_1ui_ElisaCanvasActivity_nativeImeReady(
        JNIEnv *env, jclass self) {
    (void)env; (void)self;
    return (jint)elisa_android_wants_keyboard();
}

JNIEXPORT void JNICALL Java_org_elisa_1ui_ElisaCanvasActivity_nativeImeReport(
        JNIEnv *env, jclass self, jstring tag) {
    (void)self;
    const char *label = tag == NULL ? "?" : (*env)->GetStringUTFChars(env, tag, NULL);
    __android_log_print(ANDROID_LOG_INFO, "elisa-ui", "ime %s text=[%s] marked=%d",
                        label == NULL ? "?" : label,
                        elisa_android_ime_text(), (int)elisa_android_ime_marked_units());
    if (tag != NULL && label != NULL) (*env)->ReleaseStringUTFChars(env, tag, label);
}
