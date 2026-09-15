#!/usr/bin/env bash
# Build an Android application from an example's Android entry point.
#
# Everything is cross-compiled for arm64: the Elisa sources and the runtime
# through the compiler's own `-emit exe` path, driven by a wrapper that makes
# the NDK's clang produce a shared library and add the host, the Skia shims,
# Skia itself and the platform libraries. The result is a NativeActivity APK
# with one small Java IME bridge, signed with a debug key.
#
# Usage: SKIA_ROOT=~/skia scripts/build_android.sh [example]
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../Elisa-compiler}"
EXAMPLE="${1:-storefront}"
[[ "$EXAMPLE" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "invalid Android example name: $EXAMPLE" >&2; exit 2; }
ENTRY="$ROOT/examples/$EXAMPLE/android_main.elisa"
SKIA_ROOT="${SKIA_ROOT:?set SKIA_ROOT to the pinned checkout from third_party/skia.lock}"
SKIA_OUT="${SKIA_ANDROID_OUT:-$SKIA_ROOT/out/elisa-android-arm64}"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
NDK="${ANDROID_NDK_ROOT:-$(ls -d "$SDK"/ndk/* 2>/dev/null | sort -V | tail -1)}"
API="${ELISA_UI_ANDROID_API:-30}"
BUILD_TOOLS="$(ls -d "$SDK"/build-tools/* 2>/dev/null | sort -V | tail -1)"
PLATFORM_JAR="$(ls "$SDK"/platforms/*/android.jar 2>/dev/null | sort -V | tail -1)"
TRIPLE="aarch64-linux-android$API"
case "$(uname -s):$(uname -m)" in
  Darwin:arm64) ndk_host_tags=(darwin-arm64 darwin-x86_64) ;;
  Darwin:*) ndk_host_tags=(darwin-x86_64 darwin-arm64) ;;
  Linux:*) ndk_host_tags=(linux-$(uname -m) linux-x86_64) ;;
  *) ndk_host_tags=() ;;
esac
TOOLCHAIN=""
for host_tag in "${ndk_host_tags[@]}"; do
  candidate="$NDK/toolchains/llvm/prebuilt/$host_tag"
  if [[ -x "$candidate/bin/$TRIPLE-clang" ]]; then
    TOOLCHAIN="$candidate"
    break
  fi
done
[[ -n "$TOOLCHAIN" ]] || { echo "no NDK LLVM toolchain for $(uname -s)/$(uname -m) under $NDK" >&2; exit 2; }
CLANG="$TOOLCHAIN/bin/$TRIPLE-clang"
CLANGXX="$TOOLCHAIN/bin/$TRIPLE-clang++"

[[ -f "$ENTRY" ]] || { echo "no Android entry: $ENTRY" >&2; exit 2; }
[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "no stage1 product at $STAGE1/bin/elisac-stage1" >&2; exit 2; }
[[ -x "$CLANG" ]] || { echo "no NDK clang at $CLANG" >&2; exit 2; }
[[ -f "$SKIA_OUT/libskia.a" ]] || { echo "no Android Skia at $SKIA_OUT/libskia.a (run scripts/build_skia_android.sh)" >&2; exit 2; }
[[ -n "$BUILD_TOOLS" && -n "$PLATFORM_JAR" ]] || { echo "no build-tools or platform under $SDK" >&2; exit 2; }

OUT="$ROOT/build/android/$EXAMPLE"
mkdir -p "$OUT"
LIB="lib$EXAMPLE"

# The runtime object for this triple, with the profiler hook fallbacks.
"$STAGE1/bin/elisac-stage1" -emit obj -O0 -target-triple "$TRIPLE" \
  -o "$OUT/runtime_core.o" "$STAGE1/elisacore_std/native_runtime_support.elisa"
bash "$STAGE1/scripts/write_profiler_hook_fallbacks.sh" > "$OUT/profiler_hooks.c"
"$CLANG" -c -fPIC -o "$OUT/profiler_hooks.o" "$OUT/profiler_hooks.c"
"$CLANG" -c -fPIC -o "$OUT/android_runtime_support.o" "$ROOT/src/platform/android/android_runtime_support.c"
"$CLANG" -r -o "$OUT/elisacore_runtime.o" "$OUT/runtime_core.o" "$OUT/profiler_hooks.o" "$OUT/android_runtime_support.o"

# The host, the glue and the Skia shims.
CXXFLAGS=(-std=c++17 -fPIC -O1 -Wall -Wextra -Werror -Wno-unused-parameter -DSK_BUILD_FOR_ANDROID -I"$SKIA_ROOT" -I"$ROOT")
# The glue runs android_main on a thread it creates with the default stack,
# which the retained widget layer overflows on its first layout. The glue is
# compiled here, so its one pthread_create is given a stack the size the
# process's main thread has -- 64 MB is virtual until touched.
sed 's|pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);|pthread_attr_setdetachstate(\&attr, PTHREAD_CREATE_DETACHED); pthread_attr_setstacksize(\&attr, 64u << 20);|' \
  "$NDK/sources/android/native_app_glue/android_native_app_glue.c" > "$OUT/android_native_app_glue.c"
grep -q "pthread_attr_setstacksize" "$OUT/android_native_app_glue.c" || { echo "android: the glue's thread creation was not found" >&2; exit 2; }
"$CLANG" -c -fPIC -O1 -w -I"$NDK/sources/android/native_app_glue" \
  -o "$OUT/native_app_glue.o" "$OUT/android_native_app_glue.c"
"$CLANGXX" -c "${CXXFLAGS[@]}" -I"$NDK/sources/android/native_app_glue" \
  -o "$OUT/android_skia_host.o" "$ROOT/src/platform/android/android_skia_host.cpp"
"$CLANGXX" -c "${CXXFLAGS[@]}" -o "$OUT/android_clipboard.o" "$ROOT/src/platform/android/android_clipboard.cpp"
"$CLANG" -c -fPIC -o "$OUT/android_ime_jni.o" "$ROOT/src/platform/android/android_ime_jni.c"
"$CLANGXX" -c "${CXXFLAGS[@]}" -o "$OUT/skia_canvas_shim.o" "$ROOT/src/platform/skia/skia_canvas_shim.cpp"
"$CLANGXX" -c "${CXXFLAGS[@]}" -o "$OUT/skia_text_shim.o" "$ROOT/src/platform/skia/skia_text_shim.cpp"

# The link driver the compiler will invoke: a shared library, page-aligned
# for 16 KB devices, with android_main exported for the NativeActivity.
LINKER="$OUT/android_clang.sh"
cat > "$LINKER" <<LINK
#!/usr/bin/env bash
set -euo pipefail
# The compiler's link line is written for the host it runs on; the one flag
# it carries that lld does not know is dropped here. The driver is the C one:
# the compiler hands over a C file of weak fallbacks, and a C++ driver would
# mangle every name in it.
args=()
for arg in "\$@"; do
  case "\$arg" in
    -Wl,-dead_strip|-dead_strip) ;;
    *) args+=("\$arg") ;;
  esac
done
printf '%s\\n' "\${args[@]}" > "$OUT/link_args.log"
exec "$CLANG" -shared -fPIC -Wl,-z,max-page-size=16384 -Wl,--no-undefined \\
  "\${args[@]}" \\
  "$OUT/android_skia_host.o" "$OUT/native_app_glue.o" \\
  "$OUT/skia_canvas_shim.o" "$OUT/skia_text_shim.o" "$OUT/android_clipboard.o" \
  "$OUT/android_ime_jni.o" \\
  "$SKIA_OUT/libskia.a" -lc++_static -lc++abi -landroid -llog -lm -ldl -lz
LINK
chmod +x "$LINKER"

SO="$OUT/$LIB.so"
ELISA_CLANG="$LINKER" ELISA_RUNTIME_OBJ="$OUT/elisacore_runtime.o" \
  "$STAGE1/bin/elisac-stage1" -emit exe -O0 -target-triple "$TRIPLE" \
  -o "$SO" "$ENTRY"

# The APK: a manifest with no code, the library at its ABI path, aligned and
# signed with a debug key made here if the SDK has not made one already.
STAGE="$OUT/apk"
rm -rf "$STAGE"
mkdir -p "$STAGE/lib/arm64-v8a"
cp "$SO" "$STAGE/lib/arm64-v8a/$LIB.so"
cat > "$OUT/AndroidManifest.xml" <<MANIFEST
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="org.elisa_ui.$EXAMPLE" android:versionCode="1" android:versionName="1.0">
  <!-- 34, not 35: from 35 on the window is laid out edge to edge under the
       system bars and the content rect no longer says where they are. At 34
       the window sits between them, which is the safe area this host wants. -->
  <uses-sdk android:minSdkVersion="$API" android:targetSdkVersion="34"/>
  <!-- memtagMode off: the heap tagging Android turns on for this device makes
       every allocation in the renderer an order of magnitude dearer, and the
       first frame took thirty seconds with it on. debuggable: this APK is
       signed with a generated debug key and is a development build; the flag
       is what lets simpleperf attach to it. -->
  <application android:label="elisa-ui $EXAMPLE" android:hasCode="true"
      android:extractNativeLibs="false" android:memtagMode="off" android:debuggable="true"
      android:theme="@android:style/Theme.Material.NoActionBar">
    <activity android:name="org.elisa_ui.ElisaCanvasActivity" android:exported="true"
        android:configChanges="orientation|screenSize|screenLayout|keyboardHidden|density">
      <meta-data android:name="android.app.lib_name" android:value="$EXAMPLE"/>
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
      </intent-filter>
    </activity>
  </application>
</manifest>
MANIFEST
UNALIGNED="$OUT/$EXAMPLE-unaligned.apk"
# --- the Java half ------------------------------------------------------
# ONE CLASS, AND IT BUYS IME COMPOSITION. hasCode was false here for as long as
# the canvas needed nothing from Java, which was true until the day a Chinese
# or Japanese keyboard had to reach a field this backend paints itself:
# composition arrives through onCreateInputConnection on a View, and a plain
# NativeActivity has none. The dex is the price of that, and it is the whole
# price -- the class decides nothing and holds no editing state.
rm -rf "$OUT/classes"
mkdir -p "$OUT/classes"
javac_log="$OUT/javac.log"
javac -source 8 -target 8 -nowarn -bootclasspath "$PLATFORM_JAR" -classpath "$PLATFORM_JAR" \
  -d "$OUT/classes" "$ROOT/src/platform/android/java/org/elisa_ui/ElisaCanvasActivity.java" >"$javac_log" 2>&1 || {
    javac_status=$?
    cat "$javac_log" >&2
    echo "android: javac failed" >&2
    exit "$javac_status"
  }
grep -v "^warning:" "$javac_log" || true
[[ -f "$OUT/classes/org/elisa_ui/ElisaCanvasActivity.class" ]] || { echo "android: javac produced no canvas activity" >&2; exit 2; }
# Run from the class root so the file list is relative: this project's own path
# has a space in it, and an unquoted expansion of absolute names splits.
(cd "$OUT/classes" && find . -name '*.class' | sort > "$OUT/classes.list")
rm -f "$OUT/classes.dex"
(cd "$OUT/classes" && xargs "$BUILD_TOOLS/d8" --min-api "$API" --output "$OUT" < "$OUT/classes.list")
[[ -f "$OUT/classes.dex" ]] || { echo "android: d8 produced no dex" >&2; exit 2; }
cp "$OUT/classes.dex" "$STAGE/classes.dex"

"$BUILD_TOOLS/aapt2" link -o "$UNALIGNED" --manifest "$OUT/AndroidManifest.xml" -I "$PLATFORM_JAR"
# The dex is deflated and the library is stored: only the .so needs to stay
# uncompressed so the loader can map it in place on a 16 KB-page device.
(cd "$STAGE" && zip -q -X "$UNALIGNED" classes.dex)
(cd "$STAGE" && zip -q -0 -X "$UNALIGNED" "lib/arm64-v8a/$LIB.so")
APK="$OUT/$EXAMPLE.apk"
rm -f "$APK"
# -P 16, not -p: -p aligns the library to 4 KB, and a device with 16 KB pages
# refuses to map it. The 4 there is the zip entry alignment, which is separate.
"$BUILD_TOOLS/zipalign" -P 16 -f 4 "$UNALIGNED" "$APK"
KEYSTORE="${ELISA_UI_ANDROID_KEYSTORE:-$HOME/.android/debug.keystore}"
if [[ ! -f "$KEYSTORE" ]]; then
  mkdir -p "$(dirname -- "$KEYSTORE")"
  keytool -genkeypair -keystore "$KEYSTORE" -storepass android -keypass android -alias androiddebugkey \
    -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi
"$BUILD_TOOLS/apksigner" sign --ks "$KEYSTORE" --ks-pass pass:android --key-pass pass:android \
  --ks-key-alias androiddebugkey "$APK"
echo "built $APK"
