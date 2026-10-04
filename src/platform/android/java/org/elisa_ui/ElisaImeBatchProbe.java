package org.elisa_ui;

import android.util.Log;
import android.view.View;
import android.view.inputmethod.ExtractedText;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;

/** Opt-in runtime check using the production connection and native snapshot. */
final class ElisaImeBatchProbe implements Runnable {
    private final View view;
    private final InputConnection connection;
    private int phase;
    private int attempts;

    private ElisaImeBatchProbe(View view, InputConnection connection) {
        this.view = view;
        this.connection = connection;
    }

    static void start(View view, InputConnection connection) {
        view.postDelayed(new ElisaImeBatchProbe(view, connection), 100);
    }

    private void require(boolean condition, String detail) {
        if (!condition) throw new IllegalStateException(detail);
    }

    @Override public void run() {
        try {
            ExtractedText document = connection.getExtractedText(null, 0);
            require(document != null, "missing document");
            String value = document.text.toString();
            if (phase == 0) {
                if (!value.equals("\u4f60\u597d\ud83d\udc4b")) {
                    require(++attempts < 100, "initial publication timed out");
                    view.postDelayed(this, 20);
                    return;
                }
                require(connection.beginBatchEdit(), "outer begin rejected");
                require(connection.beginBatchEdit(), "nested begin rejected");
                require(connection.performContextMenuAction(android.R.id.selectAll), "select all rejected");
                require(connection.commitText("batch\ud83d\ude00", 1), "commit rejected");
                ElisaCanvasActivity.nativeImeReport("batch-inside");
                require(connection.endBatchEdit(), "nested end lost outer batch");
                phase = 1;
                // Allow the native owner thread to drain while the outer batch
                // remains open: readback must still expose the prior snapshot.
                view.postDelayed(this, 300);
            } else if (phase == 1) {
                require(value.equals("\u4f60\u597d\ud83d\udc4b"), "open batch published edits");
                require(!connection.endBatchEdit(), "outer end remained nested");
                phase = 2;
                attempts = 0;
                view.postDelayed(this, 20);
            } else if (phase == 2) {
                if (!value.equals("batch\ud83d\ude00")) {
                    require(++attempts < 100, "end publication timed out");
                    view.postDelayed(this, 20);
                    return;
                }
                require(document.selectionStart == 7 && document.selectionEnd == 7,
                        "UTF-16 caret mismatch");
                require(connection.performContextMenuAction(android.R.id.selectAll), "clipboard selection rejected");
                phase = 7;
                attempts = 0;
                view.postDelayed(this, 300);
            } else if (phase == 7) {
                if (document.selectionStart != 0 || document.selectionEnd != 7) {
                    require(++attempts < 100, "menu selection publication timed out");
                    view.postDelayed(this, 20);
                    return;
                }
                require(connection.performContextMenuAction(android.R.id.copy), "copy rejected");
                require(connection.commitText("discard", 1), "clipboard overwrite rejected");
                phase = 3;
                attempts = 0;
                view.postDelayed(this, 20);
            } else if (phase == 3) {
                if (!value.equals("discard")) {
                    require(++attempts < 100, "overwrite publication timed out");
                    view.postDelayed(this, 20);
                    return;
                }
                require(connection.performContextMenuAction(android.R.id.selectAll), "overwrite selection rejected");
                require(connection.performContextMenuAction(android.R.id.paste), "copied paste rejected");
                phase = 4;
                attempts = 0;
                view.postDelayed(this, 20);
            } else if (phase == 4) {
                if (!value.equals("batch\ud83d\ude00")) {
                    require(++attempts < 100, "copy restoration timed out");
                    view.postDelayed(this, 20);
                    return;
                }
                require(connection.performContextMenuAction(android.R.id.selectAll), "cut selection rejected");
                require(connection.performContextMenuAction(android.R.id.cut), "cut rejected");
                phase = 5;
                attempts = 0;
                view.postDelayed(this, 20);
            } else if (phase == 5) {
                if (!value.isEmpty()) {
                    require(++attempts < 100, "cut publication timed out");
                    view.postDelayed(this, 20);
                    return;
                }
                require(connection.performContextMenuAction(android.R.id.paste), "cut paste rejected");
                phase = 6;
                attempts = 0;
                view.postDelayed(this, 20);
            } else {
                if (!value.equals("batch\ud83d\ude00")) {
                    require(++attempts < 100, "clipboard restoration timed out");
                    view.postDelayed(this, 20);
                    return;
                }
                connection.closeConnection();
                require(!connection.commitText("closed", 1), "closed connection accepted edit");
                require(!connection.performContextMenuAction(android.R.id.selectAll), "closed connection accepted action");
                require(!connection.performContextMenuAction(android.R.id.paste), "closed connection accepted paste");
                require(connection.getExtractedText(null, 0) == null, "closed connection read document");
                Log.i("elisa-ui", "ime-batch passed nested publication utf16 close");
                Log.i("elisa-ui", "ime-clipboard passed copy cut unicode-paste close");
                InputConnection menuConnection = ((ElisaInputView)view).onCreateInputConnection(new EditorInfo());
                require(menuConnection != null, "menu connection unavailable");
                ElisaMenuCopyProbe.start(view, menuConnection);
            }
        } catch (RuntimeException failure) {
            connection.closeConnection();
            Log.e("elisa-ui", "ime-batch failed " + failure.getMessage());
        }
    }
}
