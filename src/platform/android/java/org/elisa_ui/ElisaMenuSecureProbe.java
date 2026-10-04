package org.elisa_ui;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.util.Log;
import android.text.InputType;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.view.View;

/** Opt-in device probe for secure-purpose menu policy; never logs the dummy value. */
final class ElisaMenuSecureProbe implements Runnable {
    private static final String TEST_VALUE = "probe-secret";
    private static final String CLIPBOARD_SENTINEL = "batch\ud83d\ude00";
    private final ElisaInputView view;
    private ClipboardManager clipboard;
    private InputConnection connection;
    private int attempts;
    private int phase;
    private int settledChecks;
    private long owner;

    private ElisaMenuSecureProbe(ElisaInputView view) { this.view = view; }

    static void start(ElisaInputView view) {
        view.postDelayed(new ElisaMenuSecureProbe(view), 150);
    }

    @Override public void run() {
        long[] state = ElisaCanvasActivity.nativeImeConnection();
        if (phase == 0) {
            if (state == null || state.length < 4 || state[0] == 0 || state[1] != 1) {
                retry("secure field not focused");
                return;
            }
            owner = state[0];
            EditorInfo traits = new EditorInfo();
            connection = view.onCreateInputConnection(traits);
            long[] current = ElisaCanvasActivity.nativeImeConnection();
            if (connection == null || current == null || current[0] != owner || current[1] != 1) {
                if (connection != null) connection.closeConnection();
                fail("secure connection changed");
                return;
            }
            if ((traits.inputType & InputType.TYPE_TEXT_VARIATION_PASSWORD) == 0 ||
                    (traits.inputType & InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS) == 0 ||
                    (traits.imeOptions & EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING) == 0) {
                connection.closeConnection();
                fail("secure IME traits missing");
                return;
            }
            Log.i("elisa-ui", "ime-menu-secure traits passed");
            clipboard = (ClipboardManager)view.getContext().getSystemService(Context.CLIPBOARD_SERVICE);
            if (clipboard == null || !hasSentinel(clipboard)) {
                connection.closeConnection();
                fail("clipboard sentinel missing");
                return;
            }
            if (!connection.commitText(TEST_VALUE, 1) ||
                    !connection.performContextMenuAction(android.R.id.selectAll) ||
                    !connection.performContextMenuAction(android.R.id.copy)) {
                connection.closeConnection();
                fail("secure edit or copy request rejected");
                return;
            }
            ElisaCanvasActivity.nativeImeReport("secure-copy-drained");
            phase = 1;
            attempts = 0;
            settledChecks = 0;
        } else {
            if (state == null || state.length < 4 || state[0] != owner || state[1] != 1) {
                fail("secure owner retired");
                return;
            }
            if (state[2] == 0 && state[3] == TEST_VALUE.length()) {
                if (++settledChecks < 4) {
                    retry("secure copy observation timed out");
                    return;
                }
                if (clipboard == null || !hasSentinel(clipboard)) {
                    fail("secure copy changed clipboard");
                    return;
                }
                Log.i("elisa-ui", "ime-menu-secure copy denied sentinel preserved");
                Log.i("elisa-ui", "ime-menu-secure ready");
                return;
            }
        }
        retry("secure selection publication timed out");
    }

    private void retry(String reason) {
        if (++attempts >= 300) { fail(reason); return; }
        view.postDelayed(this, 100);
    }

    private void fail(String reason) {
        if (clipboard != null && !hasSentinel(clipboard)) clipboard.clearPrimaryClip();
        if (connection != null) connection.closeConnection();
        Log.e("elisa-ui", "ime-menu-secure failed " + reason);
    }

    private static boolean hasSentinel(ClipboardManager clipboard) {
        ClipData data = clipboard.getPrimaryClip();
        return data != null && data.getItemCount() == 1 &&
            CLIPBOARD_SENTINEL.contentEquals(data.getItemAt(0).getText() == null ? "" : data.getItemAt(0).getText());
    }
}
