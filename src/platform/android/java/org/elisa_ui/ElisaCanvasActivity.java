package org.elisa_ui;

import android.app.NativeActivity;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.text.Editable;
import android.view.View;
import android.view.inputmethod.BaseInputConnection;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;

// IME COMPOSITION FOR THE PAINTED BACKEND.
//
// The Skia canvas draws its own text field, so the framework owns the caret and
// every editing decision -- which is fine for Latin typing, where the keyboard
// sends finished characters. It is not fine for most of the world. Pinyin, kana,
// Hangul and handwriting all arrive as a COMPOSING run: a provisional, usually
// underlined stretch the user is still choosing, replaced again and again until
// it is committed. That never reached this backend, and could not: composition
// is delivered through onCreateInputConnection on a Java View, and a plain
// NativeActivity has none. AInputQueue carries key events and
// ANativeActivity_showSoftInput raises the keyboard, but no InputConnection
// exists anywhere in that path.
//
// So the canvas APK gains exactly one class. That reverses the hasCode="false"
// property the Skia build had, and it is worth it: the framework's own
// composition support was already written and already driven by the two Apple
// canvases, so what was missing was this -- a View for the IME to talk to.
//
// NOTHING HERE DECIDES ANYTHING. The connection forwards the composing run and
// the commit into Elisa, which already knows how to place marked text, how to
// replace a previous composition and where the caret goes. Java holds no
// editing state at all: BaseInputConnection wants an Editable to scribble in,
// so it gets one nobody reads.
public final class ElisaCanvasActivity extends NativeActivity {
    public static native void nativeComposingText(String text, int selectionStart, int selectionLength);
    public static native void nativeCommitText(String text);

    // THE CONNECTION COMES FROM A VIEW, NOT FROM THE ACTIVITY. This was the
    // first thing to get wrong here: onCreateInputConnection is View's, and a
    // NativeActivity gives you an Activity whose content is a surface created
    // natively. So the IME needs a View of our own to talk to -- one point
    // square, focusable, drawing nothing, sitting under the native surface. It
    // exists only to answer the IME; every touch still goes to the surface.
    private ElisaInputView input;

    private static final String LIB_NAME_KEY = "android.app.lib_name";

    @Override
    protected void onCreate(Bundle state) {
        // LOAD IT OURSELVES FIRST. NativeActivity dlopens the library through
        // its own loadNativeCode path, which never tells the VM that this
        // library provides natives -- so a JNI method declared on THIS class
        // resolves to nothing and the first IME callback kills the process
        // with UnsatisfiedLinkError, which is exactly what it did. Loading the
        // same library by name registers it the way the VM expects; the second
        // load inside NativeActivity is then a no-op on an already-open image.
        try {
            android.content.pm.ActivityInfo info = getPackageManager().getActivityInfo(
                getComponentName(), PackageManager.GET_META_DATA);
            String name = info.metaData == null ? null : info.metaData.getString(LIB_NAME_KEY);
            System.loadLibrary(name == null ? "elisa" : name);
        } catch (PackageManager.NameNotFoundException missing) {
            throw new RuntimeException("the activity has no meta-data to name its library", missing);
        }
        super.onCreate(state);
        input = new ElisaInputView(this);
        addContentView(input, new android.view.ViewGroup.LayoutParams(1, 1));
        input.setFocusable(true);
        input.setFocusableInTouchMode(true);
        input.requestFocus();
    }

    private static final class ElisaInputView extends View {
        ElisaInputView(android.content.Context context) {
            super(context);
        }

        @Override
        public boolean onCheckIsTextEditor() {
            return true;
        }

        @Override
        public InputConnection onCreateInputConnection(EditorInfo out) {
            // TYPE_CLASS_TEXT with no variation, and no extract UI: this view
            // paints nothing, so a full-screen IME editor would be editing a
            // copy nobody can see.
            out.inputType = android.text.InputType.TYPE_CLASS_TEXT;
            out.imeOptions = EditorInfo.IME_FLAG_NO_EXTRACT_UI | EditorInfo.IME_ACTION_DONE;
            out.initialSelStart = 0;
            out.initialSelEnd = 0;
            return new ElisaInputConnection(this);
        }
    }

    private static final class ElisaInputConnection extends BaseInputConnection {
        ElisaInputConnection(View target) {
            // false: this connection is not "full editor" -- the editor is in
            // Elisa, and the Editable below exists only because the base class
            // insists on one.
            super(target, false);
        }

        @Override
        public boolean setComposingText(CharSequence text, int newCursorPosition) {
            String value = text == null ? "" : text.toString();
            // The composing run is the whole provisional string, and the
            // selection Elisa is told about is its end -- which is where every
            // IME on this platform puts the caret while choosing.
            nativeComposingText(value, value.length(), 0);
            return super.setComposingText(text, newCursorPosition);
        }

        @Override
        public boolean finishComposingText() {
            // An empty composing run is how the framework is told the
            // provisional text is gone, which is not the same as committing it.
            nativeComposingText("", 0, 0);
            return super.finishComposingText();
        }

        @Override
        public boolean commitText(CharSequence text, int newCursorPosition) {
            nativeCommitText(text == null ? "" : text.toString());
            // The base class keeps its own Editable in step; nothing reads it,
            // but an IME may ask this connection about its own state.
            Editable editable = getEditable();
            if (editable != null) editable.clear();
            return super.commitText(text, newCursorPosition);
        }
    }
}
