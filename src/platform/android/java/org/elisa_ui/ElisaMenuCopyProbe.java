package org.elisa_ui;

import android.content.ClipboardManager;
import android.content.ClipData;
import android.content.Context;
import android.util.Log;
import android.view.View;

/** Opt-in device gate: isolate Copy from the preceding clipboard round trip. */
final class ElisaMenuCopyProbe implements Runnable {
    private final View view;
    private final ClipboardManager clipboard;
    private int attempts;
    private ElisaMenuCopyProbe(View view, ClipboardManager clipboard) {
        this.view = view; this.clipboard = clipboard;
    }
    static void start(View view) {
        ClipboardManager clipboard = (ClipboardManager)view.getContext().getSystemService(Context.CLIPBOARD_SERVICE);
        if (clipboard == null) { Log.e("elisa-ui", "ime-menu-copy failed no clipboard"); return; }
        clipboard.clearPrimaryClip();
        view.postDelayed(new ElisaMenuCopyProbe(view, clipboard), 200);
    }
    @Override public void run() {
        ClipData clip = clipboard.getPrimaryClip();
        if (clip != null && clip.getItemCount() == 1 &&
                "batch\ud83d\ude00".contentEquals(clip.getItemAt(0).getText() == null ? "" : clip.getItemAt(0).getText())) {
            Log.i("elisa-ui", "ime-menu-copy passed Unicode clipboard");
            return;
        }
        if (++attempts >= 300) { Log.e("elisa-ui", "ime-menu-copy failed timeout"); return; }
        view.postDelayed(this, 200);
    }
}
