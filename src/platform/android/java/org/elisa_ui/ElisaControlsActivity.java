// The Activity that hosts real android.widget controls.
//
// It owns three things and no policy: the native library, one root view to
// hang the realized tree on, and the moments at which Elisa is told the
// surface exists or changed size. Everything about what goes in that root is
// decided on the other side of the boundary.
package org.elisa_ui;

import android.app.Activity;
import android.content.pm.ActivityInfo;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.os.Bundle;
import android.util.DisplayMetrics;
import android.view.ViewGroup;
import android.view.ViewTreeObserver;
import android.widget.FrameLayout;

public class ElisaControlsActivity extends Activity {
    // The library is named in the manifest the same way a NativeActivity names
    // its own, so one Activity class serves every example without a subclass.
    private static final String LIB_NAME_KEY = "android.app.lib_name";

    private FrameLayout rootView;
    private boolean started = false;
    // The size the tree was last realized against. A global layout listener
    // fires on EVERY layout pass, and realizing adds and removes views, which
    // asks for another pass: without this the two drive each other and the
    // interface never settles. Only a size that actually CHANGED is news.
    private int lastWidth = 0;
    private int lastHeight = 0;

    private native void nativeStart(float width, float height);
    private native void nativeResize(float width, float height);
    private native void nativeStop();

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        loadNativeLibrary();
        rootView = new FrameLayout(this);
        setContentView(rootView);
        ElisaControls.activity = this;
        ElisaControls.root = rootView;
        // A view has no size until it has been laid out, and a tree realized
        // against a size of zero is an interface nobody can see. The first
        // layout pass is the earliest moment there is an answer.
        rootView.getViewTreeObserver().addOnGlobalLayoutListener(
            new ViewTreeObserver.OnGlobalLayoutListener() {
                public void onGlobalLayout() {
                    int width = rootView.getWidth();
                    int height = rootView.getHeight();
                    if (width <= 0 || height <= 0) return;
                    if (width == lastWidth && height == lastHeight) return;
                    lastWidth = width;
                    lastHeight = height;
                    if (!started) {
                        started = true;
                        nativeStart(points(width), points(height));
                    } else {
                        nativeResize(points(width), points(height));
                    }
                }
            });
    }

    @Override
    public void onConfigurationChanged(Configuration configuration) {
        super.onConfigurationChanged(configuration);
        // A configuration change is news even when the pixels happen to match.
        lastWidth = 0;
        lastHeight = 0;
    }

    @Override
    protected void onDestroy() {
        if (started) nativeStop();
        ElisaControls.activity = null;
        ElisaControls.root = null;
        super.onDestroy();
    }

    // Elisa lays out in logical points; Android measures in pixels.
    private float points(int pixels) {
        DisplayMetrics metrics = getResources().getDisplayMetrics();
        return metrics.density <= 0.0f ? pixels : pixels / metrics.density;
    }

    private void loadNativeLibrary() {
        try {
            ActivityInfo info = getPackageManager().getActivityInfo(
                getComponentName(), PackageManager.GET_META_DATA);
            String name = info.metaData == null ? null : info.metaData.getString(LIB_NAME_KEY);
            System.loadLibrary(name == null ? "elisa" : name);
        } catch (PackageManager.NameNotFoundException missing) {
            throw new RuntimeException("the activity has no meta-data to name its library", missing);
        }
    }
}
