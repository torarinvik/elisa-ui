// The IME crossing for the painted backend.
//
// One JNI entry per thing the input connection reports, and neither decides
// anything: Elisa already knows how to place a composing run, how to replace
// the previous one and where the caret goes, because the two Apple canvases
// have driven exactly that API for as long as they have existed.

#include <jni.h>
#include <stdint.h>
#include <string.h>

#define ELISA_IME_TEXT_MAX 1024

extern void elisa_android_composing_text(const char *text, int32_t length,
                                         int32_t selection_start, int32_t selection_length);
extern void elisa_android_commit_text(const char *text, int32_t length);

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
