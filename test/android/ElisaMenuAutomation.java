package org.elisa_ui.menucheck;

import android.app.Activity;
import android.app.Instrumentation;
import android.app.UiAutomation;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.graphics.Rect;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.InputDevice;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;
import java.util.ArrayList;

/** Separate, self-targeted instrumentation: never restarts the showcase. */
public final class ElisaMenuAutomation extends Instrumentation {
    private int budget;
    private String copyDiagnostics = "";
    private String windowDiagnostics = "";
    private String action = "Copy";
    private String visibleAction = "Copy";
    private boolean secureAudit;
    @Override public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        if (arguments != null) action = arguments.getString("action", "Copy");
        secureAudit = "secure-audit".equals(action);
        visibleAction = secureAudit ? "Paste" : action;
        start();
    }

    private void collect(AccessibilityNodeInfo node, int depth, ArrayList<Rect> matches,
                        boolean allowWindowCopy, boolean allowFloatingToolbarCopy, Rect allowedBounds,
                        ArrayList<String> forbiddenActions) {
        if (node == null || depth > 64 || --budget < 0) return;
        String label = node.getText() == null ? "" : node.getText().toString();
        if (label.isEmpty() && node.getContentDescription() != null) label = node.getContentDescription().toString();
        String nodePackage = node.getPackageName() == null ? "" : node.getPackageName().toString();
        String viewId = node.getViewIdResourceName();
        boolean visibleEnabled = node.isVisibleToUser() && node.isEnabled();
        boolean copyOrCut = "Copy".equals(label) || "Cut".equals(label);
        if (secureAudit && node.isVisibleToUser() && label.contains("probe-secret") &&
                !forbiddenActions.contains("secure value exposed"))
            forbiddenActions.add("secure value exposed");
        if ((copyOrCut || "Paste".equals(label)) && copyDiagnostics.length() < 1000)
            copyDiagnostics += " " + label + " pkg=" + nodePackage + " visible=" + node.isVisibleToUser() +
                " enabled=" + node.isEnabled() + " id=" + viewId;
        boolean appAction = allowWindowCopy && "org.elisa_ui.showcase".equals(nodePackage);
        boolean frameworkToolbarNode = allowFloatingToolbarCopy && "com.android.systemui".equals(nodePackage) &&
            "android:id/floating_toolbar_menu_item_text".equals(viewId);
        boolean frameworkMenuItem = frameworkToolbarNode && visibleEnabled;
        if (("Paste".equals(action) || secureAudit) && frameworkToolbarNode && node.isVisibleToUser() &&
                copyOrCut && !forbiddenActions.contains(label))
            forbiddenActions.add(label);
        boolean floatingToolbarAction = frameworkMenuItem && label.equals(visibleAction);
        if ((appAction || floatingToolbarAction) && label.equals(visibleAction) && visibleEnabled) {
            AccessibilityNodeInfo clickable = node;
            for (int i = 0; i < 16 && clickable != null && !clickable.isClickable(); ++i) clickable = clickable.getParent();
            if (clickable != null && clickable.isClickable() && clickable.isEnabled()) {
                Rect bounds = new Rect(); clickable.getBoundsInScreen(bounds);
                if (!bounds.isEmpty() && allowedBounds.contains(bounds) && !matches.contains(bounds)) matches.add(bounds);
            }
        }
        for (int i = 0; i < node.getChildCount() && budget > 0; ++i)
            collect(node.getChild(i), depth + 1, matches, allowWindowCopy, allowFloatingToolbarCopy,
                allowedBounds, forbiddenActions);
    }

    @Override public void onStart() {
        Bundle result = new Bundle();
        try {
            UiAutomation automation = getUiAutomation();
            if (!"Copy".equals(action) && !"Paste".equals(action) && !secureAudit)
                throw new IllegalArgumentException("unsupported requested menu action " + action);
            AccessibilityServiceInfo service = automation.getServiceInfo();
            service.flags |= AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS |
                AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS | AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS;
            automation.setServiceInfo(service);
            ArrayList<Rect> matches = new ArrayList<>();
            ArrayList<String> forbiddenActions = new ArrayList<>();
            ArrayList<AccessibilityWindowInfo> windows = new ArrayList<>();
            for (int attempt = 0; attempt < 40; ++attempt) {
                matches.clear(); forbiddenActions.clear(); budget = 4096; copyDiagnostics = ""; windowDiagnostics = "";
                windows = new ArrayList<>(automation.getWindows());
                Rect activeShowcaseBounds = null;
                for (AccessibilityWindowInfo window : windows) {
                    AccessibilityNodeInfo root = window.getRoot();
                    String rootPackage = root == null || root.getPackageName() == null ? "" : root.getPackageName().toString();
                    if ("org.elisa_ui.showcase".equals(rootPackage) && window.isActive() && window.isFocused()) {
                        if (activeShowcaseBounds != null) throw new IllegalStateException("ambiguous active Showcase windows");
                        activeShowcaseBounds = new Rect(); window.getBoundsInScreen(activeShowcaseBounds);
                    }
                }
                if (activeShowcaseBounds == null) {
                    windowDiagnostics = " active focused Showcase window missing";
                    SystemClock.sleep(200);
                    continue;
                }
                for (AccessibilityWindowInfo window : windows) {
                    AccessibilityNodeInfo root = window.getRoot();
                    int previous = copyDiagnostics.length();
                    Rect windowBounds = new Rect(); window.getBoundsInScreen(windowBounds);
                    String rootPackage = root == null || root.getPackageName() == null ? "" : root.getPackageName().toString();
                    boolean showcaseRoot = "org.elisa_ui.showcase".equals(rootPackage);
                    boolean activeAppWindow = showcaseRoot && window.isActive() && window.isFocused();
                    CharSequence title = window.getTitle();
                    boolean floatingToolbarWindow = showcaseRoot && window.getType() == AccessibilityWindowInfo.TYPE_APPLICATION &&
                        title != null && "Popup Window".contentEquals(title) && Rect.intersects(activeShowcaseBounds, windowBounds);
                    Rect actionBounds = floatingToolbarWindow ? windowBounds : activeShowcaseBounds;
                    collect(root, 0, matches, activeAppWindow || floatingToolbarWindow, floatingToolbarWindow,
                        actionBounds, forbiddenActions);
                    if (windowDiagnostics.length() < 1200) windowDiagnostics += " [window=" + window.getTitle() +
                        " type=" + window.getType() + " active=" + window.isActive() + " focused=" + window.isFocused() +
                        " bounds=" + windowBounds.toShortString() + " root=" + rootPackage + "]";
                    if (copyDiagnostics.length() != previous) copyDiagnostics += " window=" + window.getTitle() + " type=" + window.getType();
                }
                if (!forbiddenActions.isEmpty()) throw new IllegalStateException("Paste menu exposed " + forbiddenActions);
                if (matches.size() == 1) break;
                if (matches.size() > 1) throw new IllegalStateException("ambiguous " + action + " actions");
                SystemClock.sleep(200);
            }
            if (matches.size() != 1) throw new IllegalStateException("visible " + action + " action missing from " + windows.size() +
                " windows;" + copyDiagnostics + windowDiagnostics);
            Rect bounds = matches.get(0);
            if (secureAudit) {
                result.putString("stream", "elisa menu secure audit passed Paste only");
                finish(Activity.RESULT_OK, result);
                return;
            }
            long time = SystemClock.uptimeMillis();
            MotionEvent down = MotionEvent.obtain(time, time, MotionEvent.ACTION_DOWN, bounds.exactCenterX(), bounds.exactCenterY(), 0);
            MotionEvent up = MotionEvent.obtain(time, time + 50, MotionEvent.ACTION_UP, bounds.exactCenterX(), bounds.exactCenterY(), 0);
            down.setSource(InputDevice.SOURCE_TOUCHSCREEN); up.setSource(InputDevice.SOURCE_TOUCHSCREEN);
            try {
                boolean pressed = automation.injectInputEvent(down, true);
                SystemClock.sleep(50);
                if (!automation.injectInputEvent(up, true) || !pressed)
                    throw new IllegalStateException("menu touch injection rejected");
            } finally { down.recycle(); up.recycle(); }
            result.putString("stream", "elisa menu click passed " + visibleAction + " at " + bounds.toShortString());
            finish(Activity.RESULT_OK, result);
        } catch (RuntimeException failure) {
            result.putString("stream", "elisa menu click failed " + failure.getMessage());
            finish(Activity.RESULT_CANCELED, result);
        }
    }
}
