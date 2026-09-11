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

## What is not here yet

No clipboard (a NativeActivity reaches the system one only through JNI), no
text input (the soft keyboard is the same JNI problem), no accessibility, and
no configuration changes beyond resize. The manifest declares
`configChanges="orientation|screenSize|screenLayout|keyboardHidden|density"`, so
a rotation arrives as a resize rather than a restart, which the backend already
handles.
