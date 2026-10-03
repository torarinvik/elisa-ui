package org.elisa_ui;

import android.view.ActionMode;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;

/** Focus bridge; retained state, not this view's dimensions, owns editing. */
final class ElisaInputView extends View {
    ElisaInputConnection connection;
    private ActionMode menu;
    private final ElisaTextMenuState menuState = new ElisaTextMenuState();

    ElisaInputView(android.content.Context context) { super(context); }

    @Override public boolean onCheckIsTextEditor() {
        return ElisaCanvasActivity.nativeImeReady() != 0;
    }

    @Override public InputConnection onCreateInputConnection(EditorInfo out) {
        long[] snapshot = ElisaCanvasActivity.nativeImeConnection();
        if (snapshot == null || snapshot[0] == 0 || snapshot[1] < 0) return null;
        ElisaImeTraits.apply(out, (int)snapshot[1]);
        out.initialSelStart = (int)snapshot[2];
        out.initialSelEnd = (int)snapshot[3];
        if (connection != null) connection.closeConnection();
        connection = new ElisaInputConnection(this, snapshot[0]);
        return connection;
    }

    void hideMenu() {
        if (menu != null) menu.finish();
        menuState.hide();
    }

    boolean dismissMenuForBack() {
        if (menu == null) return false;
        // Keep the selection/request remembered so a subsequent unchanged
        // publication does not reopen a menu the user explicitly dismissed.
        menu.finish();
        return true;
    }

    void setPresentationActive(boolean active) {
        menuState.setActive(active);
        if (!active) hideMenu();
    }

    void updateMenu(long[] state) {
        int decision = menuState.update(state);
        if (decision == ElisaTextMenuState.KEEP) return;
        if (menu != null) menu.finish();
        if (decision == ElisaTextMenuState.HIDE) return;
        final long capturedOwner = state[0];
        final boolean readable = ElisaTextMenuState.canExport(state);
        // The 1-pixel editor bridge is intentionally not a touch overlay.
        // FloatingActionMode clips against its originating view's visible
        // bounds, so presentation must originate from the full window view.
        menu = getRootView().startActionMode(new ActionMode.Callback() {
            @Override public boolean onCreateActionMode(ActionMode mode, Menu actions) {
                if (!menuState.isActive()) return false;
                actions.add(0, android.R.id.selectAll, 0, android.R.string.selectAll);
                if (readable) {
                    actions.add(0, android.R.id.copy, 1, android.R.string.copy);
                    actions.add(0, android.R.id.cut, 2, android.R.string.cut);
                }
                actions.add(0, android.R.id.paste, 3, android.R.string.paste);
                android.util.Log.i("elisa-ui", "ime-menu created owner-bound floating request=" + (state.length > 6 ? state[6] : 0));
                return true;
            }
            @Override public boolean onPrepareActionMode(ActionMode mode, Menu actions) { return false; }
            @Override public boolean onActionItemClicked(ActionMode mode, MenuItem item) {
                if (!menuState.isActive()) { mode.finish(); return false; }
                long[] current = ElisaCanvasActivity.nativeImeConnection();
                if (current == null || current[0] != capturedOwner) { mode.finish(); return false; }
                int id = item.getItemId();
                int action = id == android.R.id.selectAll ? 1 : id == android.R.id.copy ? 2 :
                    id == android.R.id.cut ? 3 : id == android.R.id.paste ? 4 : 0;
                boolean accepted = action != 0 && ElisaCanvasActivity.nativeImeAction(capturedOwner, action);
                if (action != 1) mode.finish();
                return accepted;
            }
            @Override public void onDestroyActionMode(ActionMode mode) {
                if (menu == mode) menu = null;
                android.util.Log.i("elisa-ui", "ime-menu destroyed request=" + (state.length > 6 ? state[6] : 0));
            }
        }, ActionMode.TYPE_FLOATING);
    }

    @Override protected void onDetachedFromWindow() { hideMenu(); super.onDetachedFromWindow(); }
    @Override protected void onWindowVisibilityChanged(int visibility) {
        if (visibility != VISIBLE) hideMenu();
        super.onWindowVisibilityChanged(visibility);
    }
}
