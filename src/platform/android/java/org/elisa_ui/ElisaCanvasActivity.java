package org.elisa_ui;

import android.app.NativeActivity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.MediaStore;
import android.text.Editable;
import android.view.View;
import android.view.WindowInsets;
import android.window.OnBackInvokedCallback;
import android.window.OnBackInvokedDispatcher;
import android.view.inputmethod.BaseInputConnection;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

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
// So the canvas APK gains its small Java bridge and selection-store helper.
// That reverses the hasCode="false" property the Skia build had, and it is
// worth it: the framework's own
// composition support was already written and already driven by the two Apple
// canvases, so what was missing was this -- a View for the IME to talk to.
//
// NOTHING HERE DECIDES ANYTHING. The connection forwards the composing run and
// the commit into Elisa, which already knows how to place marked text, how to
// replace a previous composition and where the caret goes. Java holds no
// editing state at all: BaseInputConnection wants an Editable to scribble in,
// so it gets one nobody reads.
public final class ElisaCanvasActivity extends NativeActivity {
    public static native void nativeComposingText(String text, int newCursorPosition);
    public static native void nativeCommitText(String text, int newCursorPosition);

    // Probe state is answered by the framework rather than by anything in
    // Java. See startImeProbe below for why those queries exist.
    public static native int nativeImeReady();
    public static native void nativeImeReport(String tag);
    public static native void nativeKeyboardInsets(float bottom, boolean visible);
    public static native void nativeBack();
    public static native void nativePermissionResult(int slot, int generation, int state, int failure);
    public static native void nativePermissionSync(int kind, int state, int failure);
    public static native void nativePickerResult(int slot, int generation, int state,
                                                 int selectionKind, long selectionId);

    // THE CONNECTION COMES FROM A VIEW, NOT FROM THE ACTIVITY. This was the
    // first thing to get wrong here: onCreateInputConnection is View's, and a
    // NativeActivity gives you an Activity whose content is a surface created
    // natively. So the IME needs a View of our own to talk to -- one point
    // square, focusable, drawing nothing, sitting under the native surface. It
    // exists only to answer the IME; every touch still goes to the surface.
    private ElisaInputView input;
    private OnBackInvokedCallback backCallback;
    private static volatile ElisaCanvasActivity currentActivity;
    private static final int PERMISSION_REQUEST_CODE = 7314;
    private static final String PERMISSION_PREFS = "elisa.permission.requests";
    private static final int PICKER_REQUEST_CODE = 7315;
    private static final ExecutorService PICKER_IO = Executors.newFixedThreadPool(2);
    private int pendingPermissionKind = -1;
    private int pendingPermissionSlot = -1;
    private int pendingPermissionGeneration;
    private static final String STATE_PERMISSION_KIND = "elisa.permission.kind";
    private static final String STATE_PERMISSION_SLOT = "elisa.permission.slot";
    private static final String STATE_PERMISSION_GENERATION = "elisa.permission.generation";
    private int pendingPickerKind = -1;
    private int pendingPickerSlot = -1;
    private int pendingPickerGeneration;
    private static final String STATE_PICKER_KIND = "elisa.picker.kind";
    private static final String STATE_PICKER_SLOT = "elisa.picker.slot";
    private static final String STATE_PICKER_GENERATION = "elisa.picker.generation";

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
        if (state != null) {
            pendingPermissionKind = state.getInt(STATE_PERMISSION_KIND, -1);
            pendingPermissionSlot = state.getInt(STATE_PERMISSION_SLOT, -1);
            pendingPermissionGeneration = state.getInt(STATE_PERMISSION_GENERATION, 0);
            pendingPickerKind = state.getInt(STATE_PICKER_KIND, -1);
            pendingPickerSlot = state.getInt(STATE_PICKER_SLOT, -1);
            pendingPickerGeneration = state.getInt(STATE_PICKER_GENERATION, 0);
        }
        input = new ElisaInputView(this);
        View decor = getWindow().getDecorView();
        decor.setOnApplyWindowInsetsListener(new View.OnApplyWindowInsetsListener() {
            @Override
            public WindowInsets onApplyWindowInsets(View view, WindowInsets insets) {
                boolean visible = insets.isVisible(WindowInsets.Type.ime());
                android.graphics.Insets ime = insets.getInsets(WindowInsets.Type.ime());
                float density = getResources().getDisplayMetrics().density;
                float bottom = visible && density > 0.0f ? ime.bottom / density : 0.0f;
                nativeKeyboardInsets(bottom, visible);
                return insets;
            }
        });
        addContentView(input, new android.view.ViewGroup.LayoutParams(1, 1));
        input.setFocusable(true);
        input.setFocusableInTouchMode(true);
        input.requestFocus();
        currentActivity = this;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            backCallback = new OnBackInvokedCallback() {
                @Override
                public void onBackInvoked() {
                    // The retained tree is owned by android_main's thread.
                    // JNI queues this fact there; the host performs Android's
                    // default action only if Elisa leaves it unhandled.
                    nativeBack();
                }
            };
            getOnBackInvokedDispatcher().registerOnBackInvokedCallback(
                OnBackInvokedDispatcher.PRIORITY_DEFAULT, backCallback);
        }
        decor.requestApplyInsets();
        if (getIntent() != null && getIntent().getBooleanExtra(PROBE_EXTRA, false)) startImeProbe();
    }

    @Override
    protected void onDestroy() {
        if (backCallback != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getOnBackInvokedDispatcher().unregisterOnBackInvokedCallback(backCallback);
            backCallback = null;
        }
        if (currentActivity == this) currentActivity = null;
        super.onDestroy();
    }

    @Override
    protected void onResume() {
        super.onResume();
        reportPermissionSync(0);
        reportPermissionSync(1);
    }

    @Override
    protected void onSaveInstanceState(Bundle state) {
        state.putInt(STATE_PERMISSION_KIND, pendingPermissionKind);
        state.putInt(STATE_PERMISSION_SLOT, pendingPermissionSlot);
        state.putInt(STATE_PERMISSION_GENERATION, pendingPermissionGeneration);
        state.putInt(STATE_PICKER_KIND, pendingPickerKind);
        state.putInt(STATE_PICKER_SLOT, pendingPickerSlot);
        state.putInt(STATE_PICKER_GENERATION, pendingPickerGeneration);
        super.onSaveInstanceState(state);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != PICKER_REQUEST_CODE || pendingPickerSlot < 0) return;
        final int kind = pendingPickerKind;
        final int slot = pendingPickerSlot;
        final int generation = pendingPickerGeneration;
        pendingPickerKind = -1;
        pendingPickerSlot = -1;
        pendingPickerGeneration = 0;
        if (resultCode != RESULT_OK || data == null || data.getData() == null) {
            nativePickerResult(slot, generation, 3, 0, 0);
            return;
        }
        final Uri uri = data.getData();
        final ElisaCanvasActivity activity = this;
        PICKER_IO.execute(new Runnable() {
            @Override
            public void run() {
                byte[] selected = readSelectedContent(activity, uri);
                if (selected == null) {
                    nativePickerResult(slot, generation, 4, 0, 0);
                    return;
                }
                int selectionKind = selectionKindFor(activity, uri);
                if (kind == 2 && selectionKind != 1) {
                    nativePickerResult(slot, generation, 4, 0, 0);
                    return;
                }
                long selectionId = ElisaSelectionStore.remember(selected);
                if (selectionId == 0) {
                    nativePickerResult(slot, generation, 4, 0, 0);
                    return;
                }
                nativePickerResult(slot, generation, 2, selectionKind, selectionId);
            }
        });
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode != PERMISSION_REQUEST_CODE || pendingPermissionSlot < 0) return;
        final int kind = pendingPermissionKind;
        final int slot = pendingPermissionSlot;
        final int generation = pendingPermissionGeneration;
        pendingPermissionKind = -1;
        pendingPermissionSlot = -1;
        pendingPermissionGeneration = 0;
        final boolean granted = grantResults.length > 0
            && grantResults[0] == PackageManager.PERMISSION_GRANTED;
        nativePermissionResult(slot, generation, granted ? 2 : 3, granted ? 0 : 1);
    }

    @Override
    public void onBackPressed() {
        nativeBack();
    }

    public static int requestPermission(final int kind, final int slot, final int generation) {
        final ElisaCanvasActivity activity = currentActivity;
        if (activity == null || slot < 0 || generation <= 0) return 0;
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                activity.requestPermissionOnUiThread(kind, slot, generation);
            }
        });
        return 1;
    }

    private static String permissionForKind(int kind) {
        if (kind == 0) return android.Manifest.permission.CAMERA;
        if (kind == 1) return android.Manifest.permission.RECORD_AUDIO;
        return null;
    }

    private static String featureForKind(int kind) {
        if (kind == 0) return "android.hardware.camera.any";
        if (kind == 1) return "android.hardware.microphone";
        return null;
    }

    private String permissionRequestPreference(int kind) {
        return "requested." + kind;
    }

    private void requestPermissionOnUiThread(int kind, int slot, int generation) {
        final String permission = permissionForKind(kind);
        final String feature = featureForKind(kind);
        if (permission == null || feature == null) {
            nativePermissionResult(slot, generation, 6, 4);
            return;
        }
        if (!getPackageManager().hasSystemFeature(feature)) {
            nativePermissionResult(slot, generation, 5, 3);
            return;
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M
                || checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            nativePermissionResult(slot, generation, 2, 0);
            return;
        }
        if (pendingPermissionSlot >= 0) {
            nativePermissionResult(slot, generation, 6, 4);
            return;
        }
        // UiServices intentionally does not re-prompt after a denial. Its
        // records are in-memory, so preserve that policy across process
        // recreation using the host's fact that this OS request was already
        // made. A grant above still reflects an external Settings change.
        android.content.SharedPreferences preferences =
            getSharedPreferences(PERMISSION_PREFS, MODE_PRIVATE);
        if (preferences.getBoolean(permissionRequestPreference(kind), false)) {
            nativePermissionResult(slot, generation, 3, 1);
            return;
        }
        pendingPermissionKind = kind;
        pendingPermissionSlot = slot;
        pendingPermissionGeneration = generation;
        preferences.edit()
            .putBoolean(permissionRequestPreference(kind), true).apply();
        requestPermissions(new String[]{permission}, PERMISSION_REQUEST_CODE);
    }

    public static int presentPicker(final int kind, final int slot, final int generation) {
        final ElisaCanvasActivity activity = currentActivity;
        if (activity == null || (kind != 2 && kind != 5) || slot < 0 || generation <= 0) return 0;
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                activity.presentPickerOnUiThread(kind, slot, generation);
            }
        });
        return 1;
    }

    private void presentPickerOnUiThread(int kind, int slot, int generation) {
        if (pendingPickerSlot >= 0 || pendingPermissionSlot >= 0) {
            nativePickerResult(slot, generation, 4, 0, 0);
            return;
        }
        final boolean photos = kind == 2;
        final Intent intent;
        if (photos && Build.VERSION.SDK_INT >= 33) {
            intent = new Intent(MediaStore.ACTION_PICK_IMAGES);
            intent.setType("image/*");
            intent.putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, 1);
        } else {
            intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.setType(photos ? "image/*" : "*/*");
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        }
        pendingPickerKind = kind;
        pendingPickerSlot = slot;
        pendingPickerGeneration = generation;
        try {
            startActivityForResult(intent, PICKER_REQUEST_CODE);
        } catch (ActivityNotFoundException unavailable) {
            pendingPickerKind = -1;
            pendingPickerSlot = -1;
            pendingPickerGeneration = 0;
            nativePickerResult(slot, generation, 5, 0, 0);
        }
    }

    private static byte[] readSelectedContent(ElisaCanvasActivity activity, Uri uri) {
        if (activity == null || uri == null) return null;
        try (InputStream input = activity.getContentResolver().openInputStream(uri);
             ByteArrayOutputStream output = new ByteArrayOutputStream(8192)) {
            if (input == null) return null;
            byte[] chunk = new byte[8192];
            int total = 0;
            int count;
            while ((count = input.read(chunk)) != -1) {
                if (count == 0) continue;
                total += count;
                if (total > ElisaSelectionStore.MAX_BYTES_PER_SELECTION) return null;
                output.write(chunk, 0, count);
            }
            return output.toByteArray();
        } catch (Exception unreadable) {
            return null;
        }
    }

    private static int selectionKindFor(ElisaCanvasActivity activity, Uri uri) {
        String mime = activity.getContentResolver().getType(uri);
        if (mime == null) return 6;
        if (mime.startsWith("image/")) return 1;
        if (mime.startsWith("audio/")) return 2;
        if (mime.startsWith("video/")) return 3;
        if (mime.startsWith("text/")) return 4;
        if (mime.startsWith("application/")) return 5;
        return 6;
    }

    public static int readSelectedBytes(long selectionId, long offset, byte[] target) {
        return ElisaSelectionStore.read(selectionId, offset, target);
    }

    public static int releaseSelectedBytes(long selectionId) {
        return ElisaSelectionStore.release(selectionId);
    }

    private void reportPermissionSync(int kind) {
        final String permission = permissionForKind(kind);
        final String feature = featureForKind(kind);
        if (permission == null || feature == null) return;
        if (!getPackageManager().hasSystemFeature(feature)) {
            nativePermissionSync(kind, 5, 3);
            return;
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M
                || checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            nativePermissionSync(kind, 2, 0);
            return;
        }
        boolean requested = getSharedPreferences(PERMISSION_PREFS, MODE_PRIVATE)
            .getBoolean(permissionRequestPreference(kind), false);
        nativePermissionSync(kind, requested ? 3 : 0, requested ? 1 : 0);
    }

    // Called by the native owner thread only when UiBack reports Unhandled.
    // Preserve Android's pre-33 Activity behavior and its Android 12+ root-task
    // behavior instead of trapping the user in the NativeActivity.
    public static void requestUnhandledBack() {
        final ElisaCanvasActivity activity = currentActivity;
        if (activity == null) return;
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (currentActivity != activity) return;
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    if (activity.isTaskRoot()) activity.moveTaskToBack(true);
                    else activity.finish();
                } else {
                    activity.performLegacyBack();
                }
            }
        });
    }

    @SuppressWarnings("deprecation")
    private void performLegacyBack() {
        super.onBackPressed();
    }

    // NativeActivity's generic soft-input request does not target the small
    // Java editor view that owns this InputConnection. Route visibility
    // changes through that exact view on the UI thread.
    public static void requestImeShow() {
        final ElisaCanvasActivity activity = currentActivity;
        if (activity == null) return;
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                ElisaInputView view = activity.input;
                if (view == null) return;
                view.requestFocus();
                android.view.inputmethod.InputMethodManager manager =
                    (android.view.inputmethod.InputMethodManager) activity.getSystemService(
                        INPUT_METHOD_SERVICE);
                if (manager != null) {
                    manager.showSoftInput(view,
                        android.view.inputmethod.InputMethodManager.SHOW_IMPLICIT);
                }
            }
        });
    }

    public static void requestImeHide() {
        final ElisaCanvasActivity activity = currentActivity;
        if (activity == null) return;
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                ElisaInputView view = activity.input;
                if (view == null || view.getWindowToken() == null) return;
                android.view.inputmethod.InputMethodManager manager =
                    (android.view.inputmethod.InputMethodManager) activity.getSystemService(
                        INPUT_METHOD_SERVICE);
                if (manager != null) {
                    manager.hideSoftInputFromWindow(view.getWindowToken(), 0);
                }
            }
        });
    }

    private static final String PROBE_EXTRA = "elisa.ime.probe";

    // DRIVING THE CONNECTION AN IME WOULD BE HANDED.
    //
    // Composition was the one claim about this backend that rested on
    // inference. There is no CJK IME on the emulator to type pinyin into, and
    // a composing run that never arrives draws exactly as many colours as one
    // that does, so no frame check could catch it either.
    //
    // This is not a mock. ElisaInputConnection is the production class, it is
    // built by the production onCreateInputConnection, and every byte it
    // forwards crosses the same JNI boundary a real IME's would. The calls are
    // the calls a pinyin keyboard makes: a provisional run, a longer
    // provisional run, then a commit of characters the Latin key path could
    // not have produced.
    //
    // What it does NOT prove is that an IME chooses this view -- that is what
    // onCheckIsTextEditor and the EditorInfo above answer, and a keyboard
    // coming up on a real device is the evidence for it.
    private void startImeProbe() {
        final View view = input;
        view.postDelayed(new Runnable() {
            private int waited;

            @Override
            public void run() {
                // Nothing to compose into until the framework has a focused
                // text field, and reaching one is the gate's job, not this
                // probe's -- so it waits rather than guessing at a tap.
                if (nativeImeReady() == 0) {
                    if (waited++ < 100) view.postDelayed(this, 200);
                    else nativeImeReport("no-field");
                    return;
                }
                InputConnection connection = view.onCreateInputConnection(new EditorInfo());
                if (connection == null) {
                    nativeImeReport("no-connection");
                    return;
                }
                // A start-relative caret in text containing a supplementary
                // scalar proves the native cursor protocol counts UTF-16.
                connection.setComposingText("A\ud83d\ude00B", 0);
                nativeImeReport("cursor-at-start");
                connection.setComposingText("ni", 1);
                nativeImeReport("composing-1");
                connection.setComposingText("nihao", 1);
                nativeImeReport("composing-2");
                // Include a supplementary scalar: this path crosses JNI's
                // UTF-16 String boundary and must return standard UTF-8 intact.
                // A zero cursor request places the caret at the committed
                // run's start; the Elisa side must apply this before emitting
                // the change callback, just as it does for compositions.
                connection.commitText("\u4f60\u597d\ud83d\udc4b", 0);
                connection.finishComposingText();
                nativeImeReport("committed");
            }
        }, 200);
    }

    private static final class ElisaInputView extends View {
        ElisaInputView(android.content.Context context) {
            super(context);
        }

        // ANSWERED BY THE FRAMEWORK, NOT BY THIS CLASS.
        //
        // This used to return a flat true, and the cost was visible the first
        // time the canvas was watched on a device rather than read about: the
        // platform decided the app was editing text from the moment it
        // launched, and put its handwriting affordance over an Overview page
        // with no field on it at all. A view that says it is a text editor is
        // making a claim about the application's state, and the application's
        // state is in Elisa -- which already answers exactly this question for
        // the host, to decide whether the soft keyboard belongs on screen.
        @Override
        public boolean onCheckIsTextEditor() {
            return nativeImeReady() != 0;
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
            // The composing run is the whole provisional string. Forward the
            // platform's relative cursor rule; Elisa resolves it against the
            // final bounded UTF-16 run rather than assuming every IME means end.
            nativeComposingText(value, newCursorPosition);
            return super.setComposingText(text, newCursorPosition);
        }

        @Override
        public boolean finishComposingText() {
            // An empty composing run is how the framework is told the
            // provisional text is gone, which is not the same as committing it.
            nativeComposingText("", 0);
            return super.finishComposingText();
        }

        @Override
        public boolean commitText(CharSequence text, int newCursorPosition) {
            nativeCommitText(text == null ? "" : text.toString(), newCursorPosition);
            // The base class keeps its own Editable in step; nothing reads it,
            // but an IME may ask this connection about its own state.
            Editable editable = getEditable();
            if (editable != null) editable.clear();
            return super.commitText(text, newCursorPosition);
        }
    }
}
