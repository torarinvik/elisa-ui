package org.elisa_ui;

import android.text.Editable;
import android.view.View;
import android.view.inputmethod.BaseInputConnection;
import android.view.inputmethod.ExtractedText;
import android.view.inputmethod.ExtractedTextRequest;
import android.view.inputmethod.SurroundingText;

// Retained editing belongs to the native looper. The base Editable is only
// connection-local bookkeeping; rejected queued operations must not change it.
final class ElisaInputConnection extends BaseInputConnection {
    private final long owner;
    private final ElisaImeSession session;
    private boolean notificationPending;
    private int localEditDepth;
    ElisaInputConnection(View target, long capturedOwner) {
        // Full-editor mode disables BaseInputConnection's synthetic-key
        // fallback: native queued operations are the sole text delivery path.
        super(target, true);
        owner = capturedOwner;
        session = new ElisaImeSession(capturedOwner);
    }

    @Override public CharSequence getTextBeforeCursor(int count, int flags) {
        if (!session.live()) return null;
        return ElisaCanvasActivity.nativeImeReadback(owner, 0, count);
    }
    @Override public CharSequence getTextAfterCursor(int count, int flags) {
        if (!session.live()) return null;
        return ElisaCanvasActivity.nativeImeReadback(owner, 1, count);
    }
    @Override public CharSequence getSelectedText(int flags) {
        if (!session.live()) return null;
        return ElisaCanvasActivity.nativeImeReadback(owner, 2, 0);
    }

    @Override public ExtractedText getExtractedText(ExtractedTextRequest request, int flags) {
        if (!session.live()) return null;
        boolean monitor = (flags & android.view.inputmethod.InputConnection.GET_EXTRACTED_TEXT_MONITOR) != 0;
        if (monitor && request == null) return null;
        Object[] document = ElisaCanvasActivity.nativeImeDocument(owner);
        if (document == null) { session.clearMonitor(); return null; }
        int[] positions = (int[])document[1];
        ExtractedText result = new ExtractedText();
        result.text = (String)document[0];
        result.selectionStart = positions[0]; result.selectionEnd = positions[1];
        result.startOffset = 0;
        result.partialStartOffset = result.partialEndOffset = -1;
        result.flags = ExtractedText.FLAG_SINGLE_LINE;
        if (monitor) session.monitor(request.token);
        return result;
    }

    void clearMonitor() { session.clearMonitor(); }

    boolean deferNotifications() {
        if (!session.inBatch()) return false;
        notificationPending = true;
        return true;
    }

    @Override public boolean beginBatchEdit() {
        // Base bookkeeping surrounds a single already-queued operation.
        if (localEditDepth > 0) return session.live();
        if (!session.live()) return false;
        if (!session.inBatch() && !ElisaCanvasActivity.nativeImeBatch(owner, 0)) return false;
        return session.beginBatch();
    }

    @Override public boolean endBatchEdit() {
        if (localEditDepth > 0) return false;
        if (session.outermostBatch() && !ElisaCanvasActivity.nativeImeBatch(owner, 1)) {
            session.close();
            notificationPending = false;
            return false;
        }
        int depth = session.endBatch();
        if (depth == 0 && notificationPending) {
            notificationPending = false;
            ElisaCanvasActivity.requestImeSelection();
        }
        return depth > 0;
    }

    void notifyExtracted(android.view.inputmethod.InputMethodManager manager, View view, long currentOwner) {
        Integer token = session.monitorFor(currentOwner);
        if (token == null) return;
        ExtractedText document = getExtractedText(null, 0);
        if (document != null) manager.updateExtractedText(view, token, document);
    }

    @Override public void closeConnection() {
        boolean batched = session.inBatch();
        if (!session.close()) return;
        notificationPending = false;
        // Base close calls our now-guarded finish method. Enqueue at most one
        // explicit finish; owner-thread validation still rejects retired fields.
        if (batched) ElisaCanvasActivity.nativeImeBatch(owner, 2);
        else ElisaCanvasActivity.nativeFinishComposing(owner);
        super.closeConnection();
        Editable editable = super.getEditable();
        if (editable != null) editable.clear();
    }

    @Override public boolean sendKeyEvent(android.view.KeyEvent event) {
        return session.live() && super.sendKeyEvent(event);
    }

    @Override public boolean performContextMenuAction(int id) {
        if (!session.live()) return false;
        // Resolve the document end on the native owner thread, not against a
        // possibly stale or privacy-denied Java readback snapshot.
        if (id == android.R.id.selectAll) return setSelection(0, Integer.MAX_VALUE);
        if (id == android.R.id.copy) return ElisaCanvasActivity.nativeImeAction(owner, 2);
        if (id == android.R.id.cut) return ElisaCanvasActivity.nativeImeAction(owner, 3);
        if (id == android.R.id.paste) return ElisaCanvasActivity.nativeImeAction(owner, 4);
        return false;
    }

    @android.annotation.TargetApi(31)
    @Override public SurroundingText getSurroundingText(int before, int after, int flags) {
        if (before < 0 || after < 0) return null;
        ExtractedText document = getExtractedText(null, 0);
        if (document == null) return null;
        int[] window = ElisaImeWindow.bounds(document.text, document.selectionStart, document.selectionEnd, before, after);
        return new SurroundingText(document.text.subSequence(window[0], window[1]), window[2], window[3], window[0]);
    }

    @Override
    public boolean setComposingText(CharSequence text, int cursor) {
        if (!session.live()) return false;
        String value = text == null ? "" : text.toString();
        if (!ElisaCanvasActivity.nativeComposingText(owner, value, cursor)) return false;
        ++localEditDepth;
        try { return super.setComposingText(text, cursor); }
        finally { --localEditDepth; }
    }

    @Override
    public boolean finishComposingText() {
        if (!session.live()) return false;
        if (!ElisaCanvasActivity.nativeFinishComposing(owner)) return false;
        ++localEditDepth;
        try { return super.finishComposingText(); }
        finally { --localEditDepth; }
    }

    @Override
    public boolean commitText(CharSequence text, int cursor) {
        if (!session.live()) return false;
        if (!ElisaCanvasActivity.nativeCommitText(owner, text == null ? "" : text.toString(), cursor)) return false;
        Editable editable = getEditable();
        if (editable != null) editable.clear();
        ++localEditDepth;
        try { return super.commitText(text, cursor); }
        finally { --localEditDepth; }
    }

    @Override
    public boolean setSelection(int start, int end) {
        if (!session.live()) return false;
        if (!ElisaCanvasActivity.nativeSelection(owner, start, end, false)) return false;
        // The local Editable need not contain the full retained document.
        Editable editable = getEditable();
        if (editable != null && start <= editable.length() && end <= editable.length()) {
            ++localEditDepth;
            try { super.setSelection(start, end); }
            finally { --localEditDepth; }
        }
        return true;
    }

    @Override public boolean setComposingRegion(int start, int end) {
        if (!session.live() || !ElisaCanvasActivity.nativeSelection(owner, start, end, true)) return false;
        ++localEditDepth;
        try { super.setComposingRegion(start, end); }
        finally { --localEditDepth; }
        return true;
    }

    @Override
    public boolean deleteSurroundingText(int before, int after) {
        if (!session.live()) return false;
        if (!ElisaCanvasActivity.nativeDeleteSurrounding(owner, before, after, false)) return false;
        ++localEditDepth;
        try { super.deleteSurroundingText(before, after); }
        finally { --localEditDepth; }
        return true;
    }

    @Override
    public boolean deleteSurroundingTextInCodePoints(int before, int after) {
        if (!session.live()) return false;
        if (!ElisaCanvasActivity.nativeDeleteSurrounding(owner, before, after, true)) return false;
        ++localEditDepth;
        try { super.deleteSurroundingTextInCodePoints(before, after); }
        finally { --localEditDepth; }
        return true;
    }
}
