package org.elisa_ui;

import android.content.Context;
import android.graphics.Rect;
import android.os.Bundle;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewParent;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityNodeProvider;
import java.util.Arrays;
import org.elisa_ui.ElisaAccessibilitySnapshot.Node;

/** Android accessibility adapter for the retained, custom-painted canvas. */
final class ElisaAccessibilityView extends View {
    private static final int MAX_NODES = ElisaAccessibilitySnapshot.MAX_NODES;
    private static final int NONE = ElisaAccessibilitySnapshot.NONE;
    private static final int CLICK = 1;
    private static final int FOCUS = 2;
    private static final int INCREMENT = 3;
    private static final int DECREMENT = 4;
    private static final int SET_VALUE = 5;
    private static final int LIST_FORWARD = 6;
    private static final int LIST_BACKWARD = 7;

    private byte[] wire;
    private Node[] nodes = new Node[0];
    private int accessibilityFocusedId = NONE;
    private final AccessibilityNodeProvider provider = new TreeProvider();

    ElisaAccessibilityView(Context context) {
        super(context);
        setFocusable(false);
        setClickable(false);
        setWillNotDraw(true);
        setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES);
        refreshSnapshot(false);
    }

    @Override public AccessibilityNodeProvider getAccessibilityNodeProvider() {
        return provider;
    }

    @Override public boolean onTouchEvent(MotionEvent event) {
        return false;
    }

    @Override public boolean onHoverEvent(MotionEvent event) {
        if (event.getActionMasked() == MotionEvent.ACTION_HOVER_EXIT) {
            clearAccessibilityFocus();
            return false;
        }
        if (event.getActionMasked() != MotionEvent.ACTION_HOVER_ENTER
                && event.getActionMasked() != MotionEvent.ACTION_HOVER_MOVE) return false;
        int hit = hitTest(event.getX(), event.getY());
        if (hit == NONE) {
            clearAccessibilityFocus();
            return false;
        }
        setAccessibilityFocus(hit);
        return true;
    }

    void refreshSnapshot(boolean announce) {
        byte[] nextWire = ElisaCanvasActivity.nativeAccessibilitySnapshot();
        ElisaAccessibilitySnapshot parsed = ElisaAccessibilitySnapshot.parse(nextWire);
        if (parsed == null) return;
        boolean changed = !Arrays.equals(wire, nextWire);
        wire = nextWire;
        nodes = parsed.nodes();
        if (accessibilityFocusedId != NONE && find(accessibilityFocusedId) == null) {
            accessibilityFocusedId = NONE;
        }
        if (announce && changed && isShown()) {
            sendAccessibilityEvent(AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED);
        }
        invalidate();
    }

    private static boolean finite(float value) {
        return !Float.isNaN(value) && !Float.isInfinite(value);
    }

    private Node find(int id) {
        for (Node node : nodes) if (node.id == id) return node;
        return null;
    }

    private boolean actionable(Node node) {
        return node != null && node.action >= 0 && node.action < MAX_NODES;
    }

    private int hitTest(float x, float y) {
        Node best = null;
        float bestArea = Float.POSITIVE_INFINITY;
        float density = getResources().getDisplayMetrics().density;
        for (Node node : nodes) {
            if (node.width <= 0 || node.height <= 0) continue;
            float left = node.x * density, top = node.y * density;
            float right = left + node.width * density, bottom = top + node.height * density;
            if (x >= left && x <= right && y >= top && y <= bottom) {
                float area = node.width * node.height;
                if (area <= bestArea) { best = node; bestArea = area; }
            }
        }
        return best == null ? NONE : best.id;
    }

    private void setAccessibilityFocus(int id) {
        if (accessibilityFocusedId == id) return;
        clearAccessibilityFocus();
        Node node = find(id);
        if (node == null) return;
        accessibilityFocusedId = id;
        sendVirtualEvent(node, AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUSED);
    }

    private void clearAccessibilityFocus() {
        if (accessibilityFocusedId == NONE) return;
        Node previous = find(accessibilityFocusedId);
        accessibilityFocusedId = NONE;
        if (previous != null) sendVirtualEvent(previous, AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUS_CLEARED);
    }

    private void sendVirtualEvent(Node node, int type) {
        ViewParent parent = getParent();
        if (parent == null || node == null) return;
        AccessibilityEvent event = AccessibilityEvent.obtain(type);
        event.setPackageName(getContext().getPackageName());
        event.setClassName(className(node.role));
        event.setSource(this, node.id);
        event.setContentDescription(node.label);
        parent.requestSendAccessibilityEvent(this, event);
    }

    private final class TreeProvider extends AccessibilityNodeProvider {
        @Override public AccessibilityNodeInfo createAccessibilityNodeInfo(int virtualViewId) {
            if (virtualViewId == HOST_VIEW_ID) {
                AccessibilityNodeInfo root = AccessibilityNodeInfo.obtain(ElisaAccessibilityView.this);
                ElisaAccessibilityView.this.onInitializeAccessibilityNodeInfo(root);
                for (Node node : nodes) if (node.parent >= NONE) root.addChild(ElisaAccessibilityView.this, node.id);
                return root;
            }
            Node node = find(virtualViewId);
            if (node == null) return null;
            AccessibilityNodeInfo info = AccessibilityNodeInfo.obtain(ElisaAccessibilityView.this, node.id);
            info.setSource(ElisaAccessibilityView.this, node.id);
            info.setPackageName(getContext().getPackageName());
            info.setClassName(className(node.role));
            info.setEnabled(node.enabled);
            info.setSelected(node.selected);
            info.setFocused(node.focused);
            info.setAccessibilityFocused(accessibilityFocusedId == node.id);
            info.setVisibleToUser(isShown());
            info.setFocusable(actionable(node) || node.role == 6 || node.role == 7 || node.role == 4 || node.role == 11);
            info.setCheckable(node.role == 2 || node.role == 3);
            info.setChecked(node.selected);
            if (node.parent < NONE && find(node.parent) != null) info.setParent(ElisaAccessibilityView.this, node.parent);
            info.setBoundsInParent(bounds(node));
            Rect screen = bounds(node);
            int[] location = new int[2];
            getLocationOnScreen(location);
            screen.offset(location[0], location[1]);
            info.setBoundsInScreen(screen);
            if (node.role == 6 || node.role == 7) {
                info.setText(node.text);
                info.setHintText(node.label);
                info.setError(null);
                info.setEditable(true);
                info.setPassword(node.role == 7);
                if (node.role == 6) info.setTextSelection(node.selectionStart, node.selectionStart + node.selectionLength);
                info.addAction(AccessibilityNodeInfo.ACTION_FOCUS);
            } else if (node.role == 4 || node.role == 5) {
                info.setContentDescription(node.label);
                if (node.hasRange) {
                    info.setRangeInfo(AccessibilityNodeInfo.RangeInfo.obtain(
                        node.role == 4 ? AccessibilityNodeInfo.RangeInfo.RANGE_TYPE_FLOAT : AccessibilityNodeInfo.RangeInfo.RANGE_TYPE_PERCENT,
                        node.role == 4 ? node.rangeMin : node.rangeMin * 100.0f,
                        node.role == 4 ? node.rangeMax : node.rangeMax * 100.0f,
                        node.role == 4 ? node.value : node.value * 100.0f));
                }
            } else if (node.role == 9 || node.role == 12 || node.role == 13) {
                info.setContentDescription(node.label);
            } else {
                info.setText(node.label);
            }
            if (node.help.length() > 0) info.setTooltipText(node.help);
            if (node.role == 11 && node.collectionCount > 0) {
                info.setScrollable(true);
                info.setCollectionInfo(AccessibilityNodeInfo.CollectionInfo.obtain(node.collectionCount, 1, true));
            }
            if (node.hasCollectionPosition && node.collectionPosition > 0) {
                info.setCollectionItemInfo(AccessibilityNodeInfo.CollectionItemInfo.obtain(
                    node.collectionPosition - 1, 1, 0, 1, false, node.selected));
            }
            for (Node child : nodes) if (child.parent == node.id) info.addChild(ElisaAccessibilityView.this, child.id);
            info.addAction(AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS);
            info.addAction(AccessibilityNodeInfo.ACTION_CLEAR_ACCESSIBILITY_FOCUS);
            if (node.role == 11 && node.enabled) {
                info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_FORWARD);
                info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_BACKWARD);
            } else if (actionable(node)) {
                if (node.role == 4) {
                    info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_FORWARD);
                    info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_BACKWARD);
                    info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SET_PROGRESS);
                } else if (node.role == 6 || node.role == 7) {
                    info.addAction(AccessibilityNodeInfo.ACTION_CLICK);
                } else {
                    info.addAction(AccessibilityNodeInfo.ACTION_CLICK);
                }
            }
            return info;
        }

        @Override public boolean performAction(int virtualViewId, int action, Bundle arguments) {
            if (action == AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS) {
                setAccessibilityFocus(virtualViewId);
                return accessibilityFocusedId == virtualViewId;
            }
            if (action == AccessibilityNodeInfo.ACTION_CLEAR_ACCESSIBILITY_FOCUS) {
                if (accessibilityFocusedId != virtualViewId) return false;
                clearAccessibilityFocus();
                return true;
            }
            Node node = find(virtualViewId);
            if (node == null || !node.enabled) return false;
            if (node.role == 11 && action == AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_FORWARD.getId()) {
                return ElisaCanvasActivity.nativeAccessibilityAction(node.id, LIST_FORWARD, 0.0f);
            }
            if (node.role == 11 && action == AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_BACKWARD.getId()) {
                return ElisaCanvasActivity.nativeAccessibilityAction(node.id, LIST_BACKWARD, 0.0f);
            }
            if (!actionable(node)) return false;
            if (action == AccessibilityNodeInfo.ACTION_FOCUS) {
                return ElisaCanvasActivity.nativeAccessibilityAction(node.id, FOCUS, 0.0f);
            }
            if (action == AccessibilityNodeInfo.ACTION_CLICK) {
                int kind = node.role == 6 || node.role == 7 ? FOCUS : CLICK;
                return ElisaCanvasActivity.nativeAccessibilityAction(node.id, kind, 0.0f);
            }
            if (action == AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_FORWARD.getId()) {
                return ElisaCanvasActivity.nativeAccessibilityAction(node.id, INCREMENT, 0.0f);
            }
            if (action == AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_BACKWARD.getId()) {
                return ElisaCanvasActivity.nativeAccessibilityAction(node.id, DECREMENT, 0.0f);
            }
            if (action == AccessibilityNodeInfo.AccessibilityAction.ACTION_SET_PROGRESS.getId()
                    && arguments != null) {
                float value = arguments.getFloat(AccessibilityNodeInfo.ACTION_ARGUMENT_PROGRESS_VALUE, Float.NaN);
                if (!finite(value)) return false;
                return ElisaCanvasActivity.nativeAccessibilityAction(node.id, SET_VALUE, value);
            }
            return false;
        }
    }

    private Rect bounds(Node node) {
        float density = getResources().getDisplayMetrics().density;
        return new Rect(Math.round(node.x * density), Math.round(node.y * density),
                        Math.round((node.x + node.width) * density),
                        Math.round((node.y + node.height) * density));
    }

    private static String className(int role) {
        switch (role) {
            case 1: return android.widget.Button.class.getName();
            case 2: return android.widget.RadioButton.class.getName();
            case 3: return android.widget.CheckBox.class.getName();
            case 4: return android.widget.SeekBar.class.getName();
            case 5: return android.widget.ProgressBar.class.getName();
            case 6: return android.widget.EditText.class.getName();
            case 7: return android.widget.EditText.class.getName();
            case 8: return android.view.ViewGroup.class.getName();
            case 9: return android.widget.ImageView.class.getName();
            case 10: return android.view.ViewGroup.class.getName();
            case 11: return android.widget.ListView.class.getName();
            case 12: return android.widget.TextView.class.getName();
            case 13: return android.widget.TextView.class.getName();
            default: return android.view.View.class.getName();
        }
    }
}
