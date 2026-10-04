package org.elisa_ui;

import android.content.ClipboardManager;
import android.content.ClipData;
import android.content.Context;
import android.util.Log;
import android.view.View;
import android.view.inputmethod.ExtractedText;
import android.view.inputmethod.InputConnection;

/** Opt-in device gate: exercise visible Copy, empty-field menu, and Paste. */
final class ElisaMenuCopyProbe implements Runnable {
    private final View view;
    private final ClipboardManager clipboard;
    private final InputConnection connection;
    private int phase;
    private int attempts;
    private ElisaMenuCopyProbe(View view, ClipboardManager clipboard, InputConnection connection) {
        this.view = view; this.clipboard = clipboard; this.connection = connection;
    }
    static void start(View view, InputConnection connection) {
        ClipboardManager clipboard = (ClipboardManager)view.getContext().getSystemService(Context.CLIPBOARD_SERVICE);
        if (clipboard == null) {
            connection.closeConnection();
            Log.e("elisa-ui", "ime-menu-copy failed no clipboard");
            return;
        }
        clipboard.clearPrimaryClip();
        view.postDelayed(new ElisaMenuCopyProbe(view, clipboard, connection), 200);
    }
    @Override public void run() {
        if (phase == 0) {
            ClipData clip = clipboard.getPrimaryClip();
            if (clip != null && clip.getItemCount() == 1 &&
                    "batch\ud83d\ude00".contentEquals(clip.getItemAt(0).getText() == null ? "" : clip.getItemAt(0).getText())) {
                Log.i("elisa-ui", "ime-menu-copy passed Unicode clipboard");
                if (!connection.performContextMenuAction(android.R.id.selectAll) || !connection.commitText("", 1)) {
                    fail("could not prepare empty field");
                    return;
                }
                phase = 1;
                attempts = 0;
            }
        } else {
            ExtractedText document = connection.getExtractedText(null, 0);
            if (document == null) { fail("menu connection retired"); return; }
            if (phase == 1 && document.text.length() == 0 && document.selectionStart == 0 && document.selectionEnd == 0) {
                Log.i("elisa-ui", "ime-menu-empty passed cleared field");
                phase = 2;
                attempts = 0;
            } else if (phase == 2 && "batch\ud83d\ude00".contentEquals(document.text)) {
                Log.i("elisa-ui", "ime-menu-paste passed Unicode clipboard");
                connection.closeConnection();
                ElisaMenuSecureProbe.start((ElisaInputView)view);
                return;
            }
        }
        if (++attempts >= 300) { fail(phase == 0 ? "copy timeout" : phase == 1 ? "empty field timeout" : "paste timeout"); return; }
        view.postDelayed(this, 200);
    }

    private void fail(String reason) {
        connection.closeConnection();
        Log.e("elisa-ui", "ime-menu probe failed " + reason);
    }
}
