# The Android backend

Android gets the same picture macOS and iOS get, by a different road. There is
no CoreGraphics here and no view that paints itself, so the frame is made the
way the headless fixtures in this repository make theirs: the host locks the
window's buffer, hands Elisa a Skia canvas over it, and the retained command
batch is replayed by [`UiSkia`](../src/platform/skia/ui_skia.elisa) — the same
painter behind every Skia frame in the project. Nothing about appearance lives
on this side. Every alpha, radius, ramp and shadow still comes from `UiPaint`.

The application is a NativeActivity with **no Java in it at all**: the APK holds
a manifest and one `.so`, and `android_main` is the entry point. That is not a
stunt, it is the shape the framework already has — Elisa owns the tree, the
host owns the window — and it keeps the whole backend readable as two files.

## The pieces

| | |
|---|---|
| [`ui_android.elisa`](../src/platform/android/ui_android.elisa) | The Elisa side: lifecycle, the frame, touch and scroll, the `elisa_android_*` entry points. |
| [`android_skia_host.cpp`](../src/platform/android/android_skia_host.cpp) | The host: window, looper, input queue, fonts, insets, and the touch-to-pan gesture. |
| [`android_runtime_support.c`](../src/platform/android/android_runtime_support.c) | Three stubs for what Bionic does not have: `sysctlbyname`, `backtrace`, `backtrace_symbols_fd`. |
| [`scripts/build_skia_android.sh`](../scripts/build_skia_android.sh) | Builds the pinned Skia for arm64 with the Android font manager. |
| [`scripts/build_android.sh`](../scripts/build_android.sh) | Cross-compiles, links, packages and signs the APK. |
| [`scripts/check_android.sh`](../scripts/check_android.sh) | The gate: builds, reads the package back, and runs it if a device is attached. |

```
SKIA_ROOT=~/skia scripts/build_skia_android.sh     # once
SKIA_ROOT=~/skia scripts/build_android.sh storefront
SKIA_ROOT=~/skia scripts/check_android.sh
```

## What the host owns, and what it does not

The host forwards facts and nothing else. It reports the window's size in
**logical points** — it divides by the density scale before it calls, so the
Elisa side never sees a device pixel — the density scale itself, the content
rect as a set of safe-area insets, a touch phase and a location, and a pointer
to a Skia canvas and a font. Elisa decides everything that follows: what a
touch means, whether the pointer arrives before the press, what is inset, what
is drawn.

Two of those deserve their own paragraph.

**A finger is a pointer, until it is a scroll.** A `Down` starts a press;
crossing eight logical points of slop turns it into a pan, at which point the
host sends the framework a `Leave` — so the control that thought it was being
pressed lets go, exactly as it would if the pointer had wandered off it — and
then feeds the movement through as scroll deltas. This is the same decision the
UIKit canvas makes with a `UIPanGestureRecognizer`; it is made here by hand
because a NativeActivity has no gesture recognizers.

**A window that is not focused takes no input.** `UiLifecycle` accepts input
only while the phase is Active, a started session is Active only if it was told
it has focus, and starting a session clears whatever focus was reported before
there was a window to focus. So the host maps the NativeActivity commands onto
the portable mobile vocabulary the UIKit backend already speaks — focus,
background, foreground, surface lost and restored, through
`elisa_android_lifecycle` — and it *remembers* the focus and states it again
after the start. Without that the window paints perfectly and answers nothing,
which is exactly what it did.

**The system bars are the content rect.** `app->contentRect` is the region
between the status bar and the gesture bar; divided by the scale it becomes
`UiResponsive::Insets`, which becomes `UiCore::set_content_insets`, which is
what keeps the rail's first mark clear of the clock. This only works because
the manifest targets SDK 34: from 35 on, a window is laid out edge to edge
under the system bars and the content rect no longer says where they are.

## Three things that will bite anyone reading the build script

**The glue's thread has the default stack.** `android_native_app_glue` runs
`android_main` on a thread it creates itself, and the retained widget layer
overflows that stack on its first layout — the crash reads `stack pointer is
not in a rw map`, which does not say "stack overflow" unless you already know
it does. The build compiles its own copy of the glue with one `sed` that adds
`pthread_attr_setstacksize(&attr, 64u << 20)`, and fails loudly if the line it
patches is not there any more.

**Memory tagging costs an order of magnitude.** With MTE on, the first frame
took thirty-four seconds and the second five. `android:memtagMode="off"` in the
manifest brings them back to the hundreds of milliseconds. The allocator the
renderer leans on is what pays for it.

**The compiler's link line is written for the host it runs on.** The Elisa
compiler drives the final link itself, so the build hands it a wrapper script
as its "clang": the wrapper drops `-dead_strip` (which lld does not know),
adds the host, the glue, the Skia shims, Skia and the platform libraries, and
asks for a shared library aligned for 16 KB pages. The wrapper drives the **C**
compiler, not the C++ one, because the compiler also hands the linker a C file
of weak fallbacks whose names a C++ driver would mangle. C++ itself is linked
statically: Android ships no `libc++_shared`, and an APK with no Java in it has
nothing to load one with.

## Fonts

Skia is built for Android with FreeType and `skia_enable_fontmgr_android=true`,
and the host asks `SkFontMgr_New_Android` for `"sans-serif"` — Roboto, on every
device that has ever shipped. The bold face goes through
`elisa_skia_set_bold_typeface`, which refuses anything lighter than semibold, so
a device without a real bold gets the renderer's synthetic stem growth instead
of a face that is bold in name only.

## Performance

Frames are drawn entirely on the CPU: this Skia is built with no GPU backend,
so a 1080x2424 frame is real work. Two changes to the Skia shim took the
storefront from roughly 600-900 ms a frame to roughly 175-250 ms on a Pixel 9
emulator, and both were the same discovery — **ask Skia to blur a round rect,
not a mask**:

- The outer shadow was an `SkImageFilters::DropShadowOnly`, which opens a layer
  and runs a general separable blur over all of it. It is now a blur mask
  filter on the offset round rect, which the rasterizer builds from one edge
  profile and stretches into a nine-patch.
- The inner shadow blurred a rectangle with a rounded hole in it. It now fills
  the shadow colour into a layer and subtracts the blurred round rect from it
  with `kDstOut`, which is the same picture — one minus the blurred shape — out
  of a shape Skia has a fast path for.

A profile after both changes is flat: outer shadow 22%, inner shadow 21%, the
rounded gradient fills 18%, the grain tile 11%. There is no single hotspot left
to remove; the next real step is a GPU surface.

To watch the numbers yourself:

```
adb shell setprop debug.elisa.trace 1
adb logcat -s elisa-ui
```

which prints a line a frame with its size, its render status, how many colours
a sparse walk of it found, and how long it took. Without the property the host
prints two lines a run: the surface it started on, and whether the pictures
took.

## Keys, text, and the keyboard

The NDK hands over a key code and a meta state, never a character: the
character is a property of the keyboard layout and the layout lives on the Java
side. So the host answers two different questions from one event.
`framework_key` says which key it is, in the framework's own numbering — a
printable key is its uppercase ASCII code and everything else is 256 and up, so
nothing above the host has ever heard of `AKEYCODE`. `printable_scalar` says
what it *means as text*, and that one is **the US layout, written out**: a
device with another layout types this one's letters and punctuation. Saying so
plainly is better than pretending otherwise; a real answer needs `getUnicodeChar`
across JNI.

Committed text crosses as one code point — which is what a key event yields —
and is encoded to UTF-8 on the Elisa side, so no host buffer has to be trusted
and no pointer has to be cast for a keystroke.

The soft keyboard follows the retained focus and nothing else: the host asks
`elisa_android_wants_keyboard` once a frame and calls
`ANativeActivity_showSoftInput` / `hideSoftInput` only when the answer changes,
because those calls are posted to the UI thread and repeating them would fight
whatever the user is doing with the keyboard themselves.

# The Android native-controls backend

Android has two backends, mirroring macOS and iOS: the Skia canvas above, and
one that owns no pixels at all
([`ui_android_controls.elisa`](../src/platform/android/ui_android_controls.elisa)).
It creates **TextViews, Buttons, CheckBoxes, RadioButtons, EditTexts, SeekBars
and ProgressBars** and lets Android draw them, lay out their text, run its own
IME and mirror right-to-left — the things you cannot get by drawing rectangles,
and the reason to want native controls at all. (TalkBack reads whatever caption
a view carries, but nothing here sets a `contentDescription` yet; see *What is
not here yet*.)

```
scripts/build_android_controls.sh showcase
```

**This is the one backend that needs Java.** Everywhere else on Android this
framework gets by without it: the canvas is a NativeActivity whose APK has
`hasCode="false"`, because a surface to draw into is the one thing the NDK
hands over directly. A real `android.widget.Button` is not — the widget toolkit
lives on the Java side and has no C API — so this APK carries a `classes.dex`
with exactly two classes and the library talks to them over JNI:

| | |
|---|---|
| [`ElisaControlsActivity.java`](../src/platform/android/java/org/elisa_ui/ElisaControlsActivity.java) | Owns the native library, one root view, and the moments Elisa is told the surface exists or changed size. |
| [`ElisaControls.java`](../src/platform/android/java/org/elisa_ui/ElisaControls.java) | A bridge of static methods: create an object, place it, set a property. No decision. |
| [`android_controls_jni.c`](../src/platform/android/android_controls_jni.c) | The crossing. One static method per entry point, looked up once. |

Every decision — which control a widget becomes, where it sits, which of its
colours may cross, what an action means — is taken in Elisa before any of that
runs. The Java is a bridge and the C is a crossing; neither has a policy in it.

**It realizes the retained tree**, the same one the Skia backend paints, through
the same `UiControls` seam the Apple backends use. `examples/showcase/android_controls_main.elisa`
is the showcase — all five pages, the same sources — as real Android views, and
nothing under `examples/showcase` changed to allow it. See
[docs/uikit-backend.md](uikit-backend.md) for what crosses the seam and what
stops at it; the rules are the seam's, not a platform's.

Three things this platform decides differently, and they are worth knowing:

- **A `SeekBar` counts whole steps.** The framework carries a unit interval, so
  the backend gives it a thousand of them, which is finer than a finger on any
  screen that has shipped.
- **A layout listener fires on every layout pass**, and realizing adds and
  removes views, which asks for another pass. Without remembering the size it
  last realized against, the Activity and the realization drive each other and
  the interface never settles — which is exactly what happened, at 24% of a
  CPU, before the Activity started comparing.
- **A view given too little room wrapped, where the framework ellipsizes.**
  The painted backends draw a single line and end it with an ellipsis; Android
  broke the caption across two lines, so the showcase's tab row read
  "Overvi / ew" and "Contro / ls". That is this backend disagreeing with its own
  framework about what a box means, so a caption is now one line with an
  ellipsis. A field is left alone: its text scrolls as you type, which is the
  platform's behaviour and the right one.

  **iOS did the same thing**, and an earlier version of this paragraph said it
  truncated. It does not: a `UILabel` defaults to one line but a `UIButton`'s
  title does not, and it *hyphenates* — "Over- / view". Both backends were
  fixed, and the claim that one of them was already correct came from assuming
  rather than from looking at it.

  The fix has a trap in it. `setSingleLine` installs a transformation method of
  its own, and that is the slot Material's Button already uses for
  `textAllCaps` — so it quietly turned every "SAVE STATE" into "Save state",
  which is the same mistake as stripping the platform's minimums: a native look
  given away to fix a layout problem. `setMaxLines(1)` leaves the
  transformation alone.

- **A native view wants to be bigger than the box it is given.** Android's
  widgets carry a minimum height, generous vertical padding and an extra line
  of font padding, all sized for a toolkit that measures its own layout. Placed
  at a box the framework already computed, a view that insists on more does not
  grow — it clips its own words. The minimums and the vertical padding go; the
  horizontal padding stays, because a check box's mark lives in it.

## Typing in a real EditText

A native field is the strongest single reason to realize native controls: it
brings the IME, autocorrect, dictation, the selection handles and the system
paste menu, none of which a framework that draws its own caret can borrow. All
of that is worth nothing if the words never reach the application, and for a
while they did not — an action carried a float and a flag, and a string had
nowhere to ride.

It now has a channel of its own. `ElisaControls`' `TextWatcher` reports in
`afterTextChanged`, which is the point the IME, autocorrect and a paste have
all finished with, so what crosses is the string the user meant rather than a
keystroke. `nativeControlText` carries it through
[`android_controls_jni.c`](../src/platform/android/android_controls_jni.c) —
`GetStringUTFChars`, whose modified UTF-8 differs from the real thing only for
NUL and for characters outside the BMP, and Elisa validates the encoding before
keeping any of it — into `UiControls::dispatch_native_text`. From there it is
the retained layer's own `UiFlat::replace_text`, not a second editing path
written for native backends: it clips on a grapheme boundary, records an undo
step, bumps the text revision and emits the change event exactly once.

**Focus has to outlive the interface.** Realizing again replaces every view,
which is how a tree that changed shows up — and it would also destroy the very
field that reported the keystroke. The realization remembers which *retained
widget* was focused (not which control index: a validation message appearing
shifts every index after it) and gives focus back to whichever view realizes
that widget, caret included.

Restoring focus is not enough on its own, and this cost real time to find:
`requestFocus` moves the cursor while the IME stays bound to the view that was
just destroyed, so the keyboard talks to a dead input connection.
`InputMethodManager.restartInput` is what rebinds it. Measured on a Pixel 9
before that call, typing five characters left one.

**And the tree is no longer rebuilt for a keystroke.** Restoring focus was not
enough on its own while every realization destroyed all forty-odd views: a
character arriving mid-rebuild had nowhere to land. Realizations now reconcile
— see [docs/uikit-backend.md](uikit-backend.md), where the rules are written
down once, because they are the seam's and not a platform's. Traced on a Pixel
9, typing `Grace` into the name field produces five `afterTextChanged` calls
and **zero** `create` calls, the retained tree takes each one, and the
application's own validation answers in the status label beside it.

One Android-specific consequence: a view's handle is its identity across a
realization, so `ElisaControls` hands slots out individually and takes them
back individually. While that table was a bump pointer that reset with the
whole interface, the first realization's handles were handed straight back out
to the second realization's controls. Attachment is idempotent for the same
reason — Android throws `IllegalStateException` for a child that still has a
parent, and through JNI a pending exception becomes a CheckJNI abort on the
*next* call, which is why that crash first appeared inside `set_action`.

## A password field is a password field

`UiHandles::secure_text_field` exists and the painted backends mask it. The
native backends carried no such fact, so the showcase's password field was a
plain `EditText` with the characters in the clear — and the platform's own
accessibility dump said so: `password="false"` on all three fields, and
`hint=""` on every one of them.

`secure` and `enabled` now travel in `ControlState`, which a backend already
receives at `create` — that ordering matters, because AppKit needs a different
class for a secure field rather than a property. Here it is an input type, and
setting it also picks the keyboard, turns off suggestions and stops the IME
learning what was typed. It is written only on a real change: `setInputType`
resets the typeface to monospace and drops the caret, so a field being typed in
would lose both on every keystroke.

The same call carries `enabled`, because a disabled control is not a greyer
one — Android changes its contrast, stops its touches and tells TalkBack it is
unavailable. And `setHelp` carries the two strings that are not the caption: a
field's placeholder becomes its hint, and a widget's help text becomes the
`contentDescription`.

Verified on a Pixel 9 through `uiautomator dump`: `password="true"` on the
secure field alone, the real placeholder on each of the three, and the
showcase's own "Show password" checkbox flipping `password` back to `false`
live — which is the reconciler carrying a state change to an adopted control.

## What is not here yet

The clipboard is here now. It was the only canvas backend in the framework
without one -- AppKit, UIKit, SDL3 and the browser all have one, and the two
native-controls backends deliberately do not, because a real `EditText` owns its
own selection and paste menu. Here the framework owns the caret, so copy and
paste are the framework's to provide.
[`android_clipboard.cpp`](../src/platform/android/android_clipboard.cpp) reaches
`ClipboardManager` over JNI off the activity the OS already handed the host,
rather than adding a Java class and a dex step the canvas otherwise does not
want. Lookups are per call and released again: a clipboard operation happens
when a person presses a key, not every frame, and a cached `jclass` would trade
a real lifetime hazard for an unmeasurable saving.

**And it is reachable.** `UiFlat`'s keyboard handler already tracks modifier
keys and already maps the accelerator chords -- `control_active() or
super_active()` with A, C, X, V and Z becomes select-all, copy, cut, paste,
undo and redo through `perform_text_action`. The host cooperates: it maps
`AKEYCODE_CTRL_LEFT` into the framework's key space and returns no text scalar
while Ctrl is held, so Ctrl+V arrives as a chord rather than as the letter V.
Every piece of that was already here; the clipboard underneath was the missing
one, and `ui_clipboard_*` returning false was the whole reason a paste did
nothing.

Verified on a Pixel 9, inside the canvas showcase: typing into the name field,
Ctrl+A (the selection highlights), Ctrl+C, then Ctrl+V into the email field
below puts the text there -- and the form's own validation answers the pasted
value with "Enter an address like ada@example.org." Copy, select-all and paste
all reach the system clipboard, and the application sees the result.

(An earlier version of this paragraph, and the commit that introduced it, said
the opposite -- that nothing could reach the clipboard because only AppKit and
UIKit call `perform_text_action`. That was wrong: those two call it from the
platform's edit MENU, which is a second route, not the only one. The chord
route lives in the shared retained layer and serves every backend. Checking
where `perform_text_action` was called from, and stopping there, is how a
present feature came to be recorded as absent.)

**IME composition is not here, and the reason is structural rather than
unfinished.** Composition -- the half-typed pinyin, the kana being chosen, the
underlined run a Japanese or Chinese keyboard shows before you commit -- is
delivered through `onCreateInputConnection` on a Java `View`. A `NativeActivity`
has no such View to override: it gets key events through `AInputQueue` and
`ANativeActivity_showSoftInput` raises the keyboard, but there is no
InputConnection anywhere in that path. The framework's side is ready and in
use elsewhere -- `UiFlat::update_marked_text` and `commit_text` are what the
UIKit and AppKit canvases drive -- so what is missing is the platform half.

Closing it means giving the canvas APK a Java class and a `classes.dex`, and
`android:hasCode="false"` is not an accident: it is the whole reason the Skia
build needs no javac, no d8 and no dex step, while the controls build next door
carries all three. That is a real trade and it belongs to whoever wants CJK
input on the painted backend, not to a passing fix.

**Android users are not without it.** The controls backend realizes a real
`EditText`, which does its own composition, its own suggestion strip and its
own dictation -- so the platform's full text story is available today by
choosing that backend. The gap is specific: a *custom-painted* Android app
cannot compose.

No configuration changes beyond resize.

Accessibility is partly here now: a widget's help text becomes the view's
`contentDescription`, so TalkBack reads more than whatever caption a view
happens to carry. What is still missing is a role or a live-region hint for
anything the platform cannot infer from the view class. The manifest declares
`configChanges="orientation|screenSize|screenLayout|keyboardHidden|density"`, so
a rotation arrives as a resize rather than a restart, which the backend already
handles.
