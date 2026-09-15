// The IME crossing for the painted backend.
//
// One JNI entry per thing the input connection reports, and neither decides
// anything: Elisa already knows how to place a composing run, how to replace
// the previous one and where the caret goes, because the two Apple canvases
// have driven exactly that API for as long as they have existed.

#include <android/log.h>
#include <jni.h>
#include <stdint.h>
#include "../common/utf8_utf16.h"

#define ELISA_IME_TEXT_MAX 1024

extern void elisa_android_composing_text(const char *text, int32_t length,
                                         int32_t new_cursor_position);
extern void elisa_android_commit_text(const char *text, int32_t length,
                                      int32_t new_cursor_position);

// READING BACK, for the gate. Composition is the one thing on this backend
// that no display could show and no frame count could catch: a composing run
// that never arrived and one that arrived twice draw the same number of
// colours. So the framework is asked what it holds, and the answer goes to
// the same log the frame trace uses.
extern const char *elisa_android_ime_text(void);
extern int32_t elisa_android_ime_marked_units(void);
extern int32_t elisa_android_ime_cursor_from_mark(void);
extern int32_t elisa_android_wants_keyboard(void);

static int elisa_ime_failed(JNIEnv *env) {
    if (env == NULL || (*env)->ExceptionCheck(env) == JNI_FALSE) return 0;
    (*env)->ExceptionClear(env);
    return 1;
}

// Java strings are UTF-16; the retained text API takes standard UTF-8. Convert
// here, while preserving the IME's selection offsets in their native UTF-16 unit.
static void elisa_ime_forward(JNIEnv *env, jstring text, int32_t new_cursor_position,
                              int composing) {
    if (env == NULL) return;
    if (text == NULL) {
        if (composing) elisa_android_composing_text("", 0, new_cursor_position);
        else elisa_android_commit_text("", 0, new_cursor_position);
        return;
    }
    jsize units_length = (*env)->GetStringLength(env, text);
    if (elisa_ime_failed(env)) return;
    const jchar *units = (*env)->GetStringChars(env, text, NULL);
    if (units == NULL) {
        (void)elisa_ime_failed(env);
        return;
    }
    if (elisa_ime_failed(env)) return;
    uint8_t utf8[ELISA_IME_TEXT_MAX];
    size_t length = elisa_utf16_to_utf8((const uint16_t *)units,
                                        (size_t)units_length, utf8, sizeof(utf8));
    if (composing) elisa_android_composing_text((const char *)utf8, (int32_t)length,
                                                 new_cursor_position);
    else elisa_android_commit_text((const char *)utf8, (int32_t)length,
                                   new_cursor_position);
    elisa_secure_clear(utf8, sizeof(utf8));
    (*env)->ReleaseStringChars(env, text, units);
}

JNIEXPORT void JNICALL Java_org_elisa_1ui_ElisaCanvasActivity_nativeComposingText(
        JNIEnv *env, jclass self, jstring text, jint new_cursor_position) {
    (void)self;
    elisa_ime_forward(env, text, (int32_t)new_cursor_position, 1);
}

JNIEXPORT void JNICALL Java_org_elisa_1ui_ElisaCanvasActivity_nativeCommitText(
        JNIEnv *env, jclass self, jstring text, jint new_cursor_position) {
    (void)self;
    elisa_ime_forward(env, text, (int32_t)new_cursor_position, 0);
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
    const char *value = elisa_android_ime_text();
    __android_log_print(ANDROID_LOG_INFO, "elisa-ui", "ime %s text=[%s] marked=%d cursor=%d",
                        (const char *)label,
                        value == NULL ? "" : value, (int)elisa_android_ime_marked_units(),
                        (int)elisa_android_ime_cursor_from_mark());
    if (tag_units != NULL) (*env)->ReleaseStringChars(env, tag, tag_units);
}
