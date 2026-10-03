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
    @Override public void onCreate(Bundle arguments) { super.onCreate(arguments); start(); }

    private void collect(AccessibilityNodeInfo node, int depth, ArrayList<Rect> matches) {
        if (node == null || depth > 64 || --budget < 0) return;
        boolean copy = "Copy".contentEquals(node.getText() == null ? "" : node.getText()) ||
            "Copy".contentEquals(node.getContentDescription() == null ? "" : node.getContentDescription());
        if (copy && copyDiagnostics.length() < 1000) copyDiagnostics += " Copy pkg=" + node.getPackageName() +
            " visible=" + node.isVisibleToUser() + " enabled=" + node.isEnabled() + " id=" + node.getViewIdResourceName();
        if ("org.elisa_ui.showcase".contentEquals(node.getPackageName() == null ? "" : node.getPackageName()) &&
                copy && node.isEnabled() && node.isVisibleToUser()) {
            AccessibilityNodeInfo clickable = node;
            for (int i = 0; i < 16 && clickable != null && !clickable.isClickable(); ++i) clickable = clickable.getParent();
            if (clickable != null && clickable.isClickable() && clickable.isEnabled()) {
                Rect bounds = new Rect(); clickable.getBoundsInScreen(bounds);
                if (!bounds.isEmpty() && !matches.contains(bounds)) matches.add(bounds);
            }
        }
        for (int i = 0; i < node.getChildCount() && budget > 0; ++i) collect(node.getChild(i), depth + 1, matches);
    }

    @Override public void onStart() {
        Bundle result = new Bundle();
        try {
            UiAutomation automation = getUiAutomation();
            AccessibilityServiceInfo service = automation.getServiceInfo();
            service.flags |= AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS |
                AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS | AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS;
            automation.setServiceInfo(service);
            ArrayList<Rect> matches = new ArrayList<>();
            for (int attempt = 0; attempt < 40; ++attempt) {
                matches.clear(); budget = 4096; copyDiagnostics = "";
                for (AccessibilityWindowInfo window : automation.getWindows()) {
                    int previous = copyDiagnostics.length();
                    collect(window.getRoot(), 0, matches);
                    if (copyDiagnostics.length() != previous) copyDiagnostics += " window=" + window.getTitle() + " type=" + window.getType();
                }
                if (matches.size() == 1) break;
                if (matches.size() > 1) throw new IllegalStateException("ambiguous Copy actions");
                SystemClock.sleep(200);
            }
            if (matches.size() != 1) throw new IllegalStateException("visible Copy action missing from " + automation.getWindows().size() + " windows;" + copyDiagnostics);
            Rect bounds = matches.get(0);
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
            result.putString("stream", "elisa menu click passed Copy at " + bounds.toShortString());
            finish(Activity.RESULT_OK, result);
        } catch (RuntimeException failure) {
            result.putString("stream", "elisa menu click failed " + failure.getMessage());
            finish(Activity.RESULT_CANCELED, result);
        }
    }
}
