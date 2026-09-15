// The Java half of the Android native-controls backend.
//
// WHY THERE IS JAVA HERE AT ALL. Everywhere else on Android this framework
// gets by without a control toolkit: the canvas backend is a NativeActivity
// whose only Java class is the IME bridge. A real android.widget.Button is not:
// the widget toolkit
// lives on the Java side and there is no C API for it, so a backend that
// realizes real controls has to be able to call it.
//
// Everything here is a BRIDGE and nothing is a decision. Which control a
// widget becomes, where it sits, what it says, which of its colours may cross
// and what an action means are all settled in Elisa before anything in this
// file runs; these methods create the object, place it and set the property.
// They are static because a static method needs a class reference and no
// instance reference, which is the smaller thing for the native side to hold.
package org.elisa_ui;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.text.TextPaint;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.view.inputmethod.InputMethodManager;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.CompoundButton;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.ProgressBar;
import android.widget.RadioButton;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.TextView;

public final class ElisaControls {
    // The control kinds, in the framework's own numbering. Kept as constants
    // rather than an enum so the two sides of the boundary read the same.
    public static final int WINDOW = 0, PANEL = 1, SCROLL_VIEW = 2, LABEL = 3;
    public static final int PUSH_BUTTON = 4, TOGGLE_BUTTON = 5, CHECK_BOX = 6, RADIO_BUTTON = 7;
    public static final int TEXT_FIELD = 8, SLIDER = 9, PROGRESS_BAR = 10;

    // The framework's event vocabulary, the half of it a control can report.
    private static final int EVENT_CLICK = 0, EVENT_CHANGE = 1;

    // A handle is an index plus one, so zero is "no control" on both sides.
    private static final int MAX_CONTROLS = 512;
    private static final View[] views = new View[MAX_CONTROLS];
    private static final int[] kinds = new int[MAX_CONTROLS];
    // A LIVE COUNT, NOT A BUMP POINTER. Reconciliation carries a control over
    // from one realization to the next, and a handle IS that control's
    // identity -- so a slot is taken and given back individually, and the next
    // create fills a hole rather than appending past everything still in use.
    // While this was a bump pointer that reset with the whole table, the first
    // realization's handles were handed straight back out to the second one's
    // controls, which is the same view table describing two different trees.
    private static int count = 0;

    static Activity activity;
    static ViewGroup root;

    // Elisa's answer to an action, which is where every policy about it lives.
    public static native void nativeControlEvent(int handle, int event, float value, boolean selected);
    public static native void nativeControlText(int handle, String text);

    private static float density() {
        return activity == null ? 1.0f : activity.getResources().getDisplayMetrics().density;
    }

    private static int px(float points) {
        return Math.round(points * density());
    }

    private static View viewOf(int handle) {
        // `count` is the number of live views, not the highest occupied slot.
        // Reconciliation releases individual slots, so a valid handle may be
        // above the live count while lower slots are holes. Bound by the
        // table itself; the slot's null value remains the liveness check.
        return handle <= 0 || handle > MAX_CONTROLS ? null : views[handle - 1];
    }

    // A SLIDER IS AN INTEGER TRACK ON THIS PLATFORM. SeekBar counts whole
    // steps, the framework carries a unit interval, and a thousand steps is
    // finer than a finger on any screen that has shipped.
    private static final int SLIDER_STEPS = 1000;

    private static int freeSlot() {
        for (int index = 0; index < MAX_CONTROLS; index += 1) {
            if (views[index] == null) return index;
        }
        return -1;
    }

    public static int create(int kind, int vertical) {
        if (activity == null || count >= MAX_CONTROLS) return 0;
        if (freeSlot() < 0) return 0;
        View view;
        switch (kind) {
            case SCROLL_VIEW:
                view = vertical != 0 ? new ScrollView(activity) : new HorizontalScrollView(activity);
                break;
            case LABEL: {
                TextView text = new TextView(activity);
                text.setGravity(Gravity.CENTER_VERTICAL);
                view = text;
                break;
            }
            case PUSH_BUTTON: view = new Button(activity); break;
            case TOGGLE_BUTTON:
            case CHECK_BOX: view = new CheckBox(activity); break;
            case RADIO_BUTTON: view = new RadioButton(activity); break;
            case TEXT_FIELD: {
                EditText field = new EditText(activity);
                field.setSingleLine(true);
                view = field;
                break;
            }
            case SLIDER: {
                SeekBar bar = new SeekBar(activity);
                bar.setMax(SLIDER_STEPS);
                view = bar;
                break;
            }
            case PROGRESS_BAR: {
                ProgressBar bar = new ProgressBar(activity, null, android.R.attr.progressBarStyleHorizontal);
                bar.setMax(SLIDER_STEPS);
                view = bar;
                break;
            }
            default: view = new FrameLayout(activity); break;
        }
        // ONE LINE, AND AN ELLIPSIS WHEN IT DOES NOT FIT.
        //
        // A box came from a layout that already decided how much room these
        // words get, and every other backend answers a box that is too small
        // the same way: the painted ones draw a single line and end it with an
        // ellipsis, and UIKit truncates. Android alone WRAPPED, so the
        // showcase's tab row read "Overvi / ew" and "Contro / ls" -- which is
        // not a platform difference worth keeping, it is this backend
        // disagreeing with its own framework about what a box means.
        //
        // A field is left alone: its text scrolls as you type rather than
        // being cut, which is the platform's behaviour and the right one.
        // setMaxLines, NOT setSingleLine. setSingleLine installs a
        // transformation method of its own, and that is the slot Material's
        // Button already uses for textAllCaps -- so it quietly turned every
        // "SAVE STATE" into "Save state". That is the same mistake as
        // stripping the platform's minimums: a native look given away to fix
        // a layout problem. setMaxLines leaves the transformation alone.
        if (view instanceof TextView && !(view instanceof EditText)) {
            TextView label = (TextView) view;
            label.setMaxLines(1);
            label.setEllipsize(android.text.TextUtils.TruncateAt.END);
        }
        int slot = freeSlot();
        views[slot] = view;
        kinds[slot] = kind;
        count += 1;
        return slot + 1;
    }

    // Give one slot back. Reconciliation releases exactly the controls the new
    // realization did not adopt, so this is the ordinary path now and
    // releaseAll is only for tearing the whole interface down.
    public static void release(int handle) {
        if (handle <= 0 || handle > MAX_CONTROLS) return;
        View view = views[handle - 1];
        if (view == null) return;
        ViewGroup parent = view.getParent() instanceof ViewGroup ? (ViewGroup) view.getParent() : null;
        if (parent != null) parent.removeView(view);
        views[handle - 1] = null;
        count -= 1;
    }

    // WHAT THE PLATFORM WANTS, MEASURED BY THE PLATFORM.
    //
    // The framework lays out before a single view exists, from numbers its
    // application's entry point supplies. Given invented ones -- a character
    // width guessed at, a line height guessed at, no idea that a Button has a
    // minimum -- it hands each control a box smaller than Android's widgets
    // are built for, and a widget that is given less than it needs does not
    // shrink: it clips its own words. The first attempt at this file answered
    // by taking the minimums and the padding AWAY, which fits the box and
    // stops it looking like Android.
    //
    // These are the other answer. Android measures its own text and its own
    // widgets, in points, before the layout runs -- so the box is big enough
    // and the control keeps everything that makes it native.
    private static final TextPaint measurePaint = new TextPaint(android.graphics.Paint.ANTI_ALIAS_FLAG);
    private static final float[] minimumHeights = new float[PROGRESS_BAR + 1];

    public static float measureTextWidth(String text, float sizePoints, boolean weighted) {
        if (activity == null || text == null) return 0.0f;
        measurePaint.setTextSize(sizePoints * density());
        measurePaint.setTypeface(weighted ? Typeface.DEFAULT_BOLD : Typeface.DEFAULT);
        return measurePaint.measureText(text) / density();
    }

    public static float textLineHeight(float sizePoints) {
        if (activity == null) return sizePoints;
        measurePaint.setTextSize(sizePoints * density());
        measurePaint.setTypeface(Typeface.DEFAULT);
        android.graphics.Paint.FontMetrics metrics = measurePaint.getFontMetrics();
        // top and bottom, NOT ascent and descent. A TextView reserves the
        // font's full extent for a line -- that is what includeFontPadding
        // means -- and a box measured from the tighter pair is a box the view
        // will clip its own descenders out of.
        return (metrics.bottom - metrics.top) / density();
    }

    // What a control of this kind is at its smallest, asked of a real one.
    // Measured once per kind and remembered: the answer is a property of the
    // theme, not of any particular control.
    public static float minimumHeight(int kind) {
        if (activity == null || kind < 0 || kind >= minimumHeights.length) return 0.0f;
        if (minimumHeights[kind] > 0.0f) return minimumHeights[kind];
        int handle = create(kind, 1);
        View probe = viewOf(handle);
        if (probe == null) return 0.0f;
        if (probe instanceof TextView) ((TextView) probe).setText("Ag");
        probe.measure(View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
                      View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED));
        float points = probe.getMeasuredHeight() / density();
        // The probe was made through the ordinary path, so it took a slot;
        // give it back rather than leaving a control nothing will ever place.
        release(handle);
        minimumHeights[kind] = points;
        return points;
    }

    // WHICH CONTROL THE USER IS TYPING IN, and where their caret sits.
    //
    // Realizing again replaces the whole interface, so without these a
    // keystroke would destroy the field that reported it: the soft keyboard
    // would drop, the caret would be lost and a composing IME would be cut off
    // mid-word. Elisa owns the handle table and asks each control in turn.
    public static boolean isFocused(int handle) {
        View view = viewOf(handle);
        return view != null && view.hasFocus();
    }

    // Java char offsets -- UTF-16 code units, the same unit iOS counts in. The
    // value only ever goes back to the platform it came from.
    public static int caret(int handle) {
        View view = viewOf(handle);
        if (!(view instanceof EditText)) return 0;
        int at = ((EditText) view).getSelectionStart();
        return at < 0 ? 0 : at;
    }

    public static void focus(final int handle, final int caret) {
        View view = viewOf(handle);
        if (view == null) return;
        view.setFocusableInTouchMode(true);
        if (!view.requestFocus()) return;
        if (view instanceof EditText) {
            EditText field = (EditText) view;
            // A caret past the end is what a realization that shortened the
            // text leaves behind; clamp rather than throwing out of setSelection.
            int length = field.getText() == null ? 0 : field.getText().length();
            field.setSelection(caret < 0 ? 0 : (caret > length ? length : caret));
        }
        // FOCUS IS NOT THE INPUT CONNECTION. requestFocus moves the cursor;
        // the IME is still bound to the view that was just destroyed, so
        // without restartInput the keyboard is talking to a dead connection
        // and every keystroke after the first one lands nowhere -- which is
        // exactly what a realization-per-keystroke produces. Measured on a
        // Pixel 9: one character arrived and the rest vanished.
        InputMethodManager ime = imeManager();
        if (ime == null) return;
        ime.restartInput(view);
        if (view instanceof EditText) ime.showSoftInput(view, InputMethodManager.SHOW_IMPLICIT);
    }

    private static InputMethodManager imeManager() {
        if (activity == null) return null;
        Object service = activity.getSystemService(android.content.Context.INPUT_METHOD_SERVICE);
        return service instanceof InputMethodManager ? (InputMethodManager) service : null;
    }

    // ATTACHING IS IDEMPOTENT, because reconciliation means a view can already
    // be where it belongs. Android throws IllegalStateException outright for a
    // child that still has a parent -- and through JNI a pending exception is
    // a CheckJNI abort on the NEXT call, which is why the crash landed in
    // set_action and not here.
    public static void addChild(int parent, int child) {
        View parentView = viewOf(parent);
        View childView = viewOf(child);
        if (!(parentView instanceof ViewGroup) || childView == null) return;
        attach((ViewGroup) parentView, childView, null);
    }

    private static void attach(ViewGroup parent, View child, ViewGroup.LayoutParams params) {
        ViewGroup current = child.getParent() instanceof ViewGroup ? (ViewGroup) child.getParent() : null;
        if (current == parent) {
            if (params != null) child.setLayoutParams(params);
            return;
        }
        if (current != null) current.removeView(child);
        if (params == null) parent.addView(child);
        else parent.addView(child, params);
    }

    // Absolute placement inside the parent, which is what the seam hands over.
    // FrameLayout margins are the standard way to say it; a ScrollView takes
    // one child and lays it out itself, so its child keeps its own size and
    // loses only its offset.
    public static void setFrame(int handle, float x, float y, float width, float height) {
        View view = viewOf(handle);
        if (view == null) return;
        ViewGroup.LayoutParams existing = view.getLayoutParams();
        ViewGroup parent = view.getParent() instanceof ViewGroup ? (ViewGroup) view.getParent() : null;
        if (parent instanceof ScrollView || parent instanceof HorizontalScrollView) {
            ViewGroup.LayoutParams params = existing != null ? existing
                : new ViewGroup.LayoutParams(px(width), px(height));
            params.width = px(width);
            params.height = px(height);
            view.setLayoutParams(params);
            return;
        }
        FrameLayout.LayoutParams params = existing instanceof FrameLayout.LayoutParams
            ? (FrameLayout.LayoutParams) existing
            : new FrameLayout.LayoutParams(px(width), px(height));
        params.width = px(width);
        params.height = px(height);
        params.leftMargin = px(x);
        params.topMargin = px(y);
        view.setLayoutParams(params);
    }

    public static void setText(int handle, String text) {
        View view = viewOf(handle);
        if (view instanceof TextView) ((TextView) view).setText(text);
    }

    public static void setTextColor(int handle, int argb) {
        View view = viewOf(handle);
        if (view instanceof TextView) ((TextView) view).setTextColor(argb);
    }

    public static void setBackgroundColor(int handle, int argb) {
        View view = viewOf(handle);
        if (view != null) view.setBackgroundColor(argb);
    }

    // The filled part of a track, under two class names.
    public static void setTintColor(int handle, int argb) {
        View view = viewOf(handle);
        if (view instanceof ProgressBar) {
            ((ProgressBar) view).setProgressTintList(android.content.res.ColorStateList.valueOf(argb));
        }
    }

    public static void setTrackColor(int handle, int argb) {
        View view = viewOf(handle);
        if (view instanceof ProgressBar) {
            ((ProgressBar) view).setProgressBackgroundTintList(android.content.res.ColorStateList.valueOf(argb));
        }
    }

    public static void setState(int handle, float value, boolean selected, boolean enabled, boolean secure) {
        View view = viewOf(handle);
        if (view == null) return;
        // A disabled control is not a greyer one: Android changes its own
        // contrast, stops its touches and tells TalkBack it is unavailable.
        view.setEnabled(enabled);
        if (view instanceof EditText) {
            EditText field = (EditText) view;
            // SECURE IS AN INPUT TYPE HERE, and setting it also picks the
            // keyboard, turns off suggestions and stops the IME learning what
            // was typed. Setting it again would reset the typeface and the
            // caret, so only a real change is written.
            int wanted = android.text.InputType.TYPE_CLASS_TEXT
                | (secure ? android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD
                          : android.text.InputType.TYPE_TEXT_VARIATION_NORMAL);
            if (field.getInputType() != wanted) {
                int caret = field.getSelectionStart();
                field.setInputType(wanted);
                // setInputType resets the typeface to monospace for a password
                // field; Android's own fields keep the theme's.
                field.setTypeface(Typeface.DEFAULT);
                int length = field.getText() == null ? 0 : field.getText().length();
                field.setSelection(caret < 0 ? 0 : (caret > length ? length : caret));
            }
            return;
        }
        if (view instanceof SeekBar) ((SeekBar) view).setProgress(Math.round(value * SLIDER_STEPS));
        else if (view instanceof ProgressBar) ((ProgressBar) view).setProgress(Math.round(value * SLIDER_STEPS));
        else if (view instanceof CompoundButton) ((CompoundButton) view).setChecked(selected);
    }

    // A placeholder is a hint on Android; the help text is what TalkBack reads
    // beyond whatever caption the view already carries. Before this, nothing
    // here set a contentDescription at all.
    public static void setHelp(int handle, String placeholder, String help) {
        View view = viewOf(handle);
        if (view == null) return;
        if (view instanceof EditText) ((EditText) view).setHint(placeholder == null ? "" : placeholder);
        // An empty description is not a description: leaving it null lets the
        // view's own text speak, which is what a Button or a TextView wants.
        view.setContentDescription(help == null || help.length() == 0 ? null : help);
    }

    // The toolkit reports the raw fact; Elisa decides what it means. A
    // listener is installed only on the kinds the seam says report one.
    public static void setAction(final int handle) {
        View view = viewOf(handle);
        if (view instanceof SeekBar) {
            ((SeekBar) view).setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
                public void onProgressChanged(SeekBar bar, int progress, boolean fromUser) {
                    if (fromUser) nativeControlEvent(handle, EVENT_CHANGE, progress / (float) SLIDER_STEPS, false);
                }
                public void onStartTrackingTouch(SeekBar bar) { }
                public void onStopTrackingTouch(SeekBar bar) { }
            });
            return;
        }
        if (view instanceof CompoundButton) {
            ((CompoundButton) view).setOnCheckedChangeListener(new CompoundButton.OnCheckedChangeListener() {
                public void onCheckedChanged(CompoundButton button, boolean checked) {
                    nativeControlEvent(handle, EVENT_CLICK, 0.0f, checked);
                }
            });
            return;
        }
        if (view instanceof EditText) {
            ((EditText) view).addTextChangedListener(new TextWatcher() {
                public void beforeTextChanged(CharSequence s, int a, int b, int c) { }
                public void onTextChanged(CharSequence s, int a, int b, int c) { }
                // afterTextChanged is the point the IME, autocorrect, a
                // dictation result and a paste have all finished with: what
                // `s` holds here is the string the user meant, which is what
                // the application needs and what the numeric event could
                // never carry.
                public void afterTextChanged(Editable s) {
                    nativeControlText(handle, s == null ? "" : s.toString());
                }
            });
            return;
        }
        if (view != null) {
            view.setOnClickListener(new View.OnClickListener() {
                public void onClick(View clicked) {
                    nativeControlEvent(handle, EVENT_CLICK, 0.0f, false);
                }
            });
        }
    }

    // Realizing again REPLACES the interface. Taking the old root off the
    // content view is the step that makes it a replacement rather than a
    // second interface stacked on the first, exactly as on iOS.
    public static void releaseAll() {
        if (root != null) root.removeAllViews();
        // Every slot, not the first `count` of them: with individual release
        // the live views are no longer a prefix of the table.
        for (int index = 0; index < MAX_CONTROLS; index += 1) views[index] = null;
        count = 0;
    }

    public static void attachRoot(int handle) {
        View view = viewOf(handle);
        if (root == null || view == null) return;
        attach(root, view, new FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
    }
}
