#!/usr/bin/env bash
# Build an Android application that realizes the retained tree as REAL
# android.widget controls.
#
# The Skia build next door is a NativeActivity whose APK deliberately has no
# code in it. This one cannot be: the widget toolkit lives on the Java side
# and has no C API, so the APK carries a classes.dex with two small classes --
# an Activity that owns the root view, and a bridge of static methods -- and
# the library talks to them over JNI. There is no Skia here at all.
#
# Usage: scripts/build_android_controls.sh [example]
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"
EXAMPLE="${1:-showcase}"
ENTRY="$ROOT/examples/$EXAMPLE/android_controls_main.elisa"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
NDK="${ANDROID_NDK_ROOT:-$(ls -d "$SDK"/ndk/* 2>/dev/null | sort -V | tail -1)}"
API="${ELISA_UI_ANDROID_API:-30}"
BUILD_TOOLS="$(ls -d "$SDK"/build-tools/* 2>/dev/null | sort -V | tail -1)"
PLATFORM_JAR="$(ls "$SDK"/platforms/*/android.jar 2>/dev/null | sort -V | tail -1)"
TRIPLE="aarch64-linux-android$API"
CLANG="$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin/$TRIPLE-clang"

[[ -f "$ENTRY" ]] || { echo "no Android controls entry: $ENTRY" >&2; exit 2; }
[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "no stage1 product at $STAGE1/bin/elisac-stage1" >&2; exit 2; }
[[ -x "$CLANG" ]] || { echo "no NDK clang at $CLANG" >&2; exit 2; }
[[ -n "$BUILD_TOOLS" && -n "$PLATFORM_JAR" ]] || { echo "no build-tools or platform under $SDK" >&2; exit 2; }
command -v javac >/dev/null || { echo "no javac on PATH" >&2; exit 2; }

OUT="$ROOT/build/android-controls/$EXAMPLE"
rm -rf "$OUT"
mkdir -p "$OUT/classes" "$OUT/apk/lib/arm64-v8a"
LIB="lib$EXAMPLE"

# --- the native library ------------------------------------------------
"$STAGE1/bin/elisac-stage1" -emit obj -O0 -target-triple "$TRIPLE" \
  -o "$OUT/runtime_core.o" "$STAGE1/elisacore_std/native_runtime_support.elisa"
bash "$STAGE1/scripts/write_profiler_hook_fallbacks.sh" > "$OUT/profiler_hooks.c"
"$CLANG" -c -fPIC -o "$OUT/profiler_hooks.o" "$OUT/profiler_hooks.c"
"$CLANG" -c -fPIC -o "$OUT/android_runtime_support.o" "$ROOT/src/platform/android/android_runtime_support.c"
"$CLANG" -c -fPIC -O1 -Wall -Wextra -Werror -o "$OUT/android_controls_jni.o" \
  "$ROOT/src/platform/android/android_controls_jni.c"
"$CLANG" -r -o "$OUT/elisacore_runtime.o" "$OUT/runtime_core.o" "$OUT/profiler_hooks.o" "$OUT/android_runtime_support.o"

# The compiler drives the final link, and the one flag it carries that lld does
# not know is dropped here. The driver is the C one: the compiler hands over a
# C file of weak fallbacks whose names a C++ driver would mangle.
LINKER="$OUT/android_clang.sh"
cat > "$LINKER" <<LINK
#!/usr/bin/env bash
set -euo pipefail
args=()
for arg in "\$@"; do
  case "\$arg" in
    -Wl,-dead_strip|-dead_strip) ;;
    *) args+=("\$arg") ;;
  esac
done
exec "$CLANG" -shared -fPIC -Wl,-z,max-page-size=16384 -Wl,--no-undefined \\
  "\${args[@]}" "$OUT/android_controls_jni.o" -llog -lm -ldl
LINK
chmod +x "$LINKER"
ELISA_CLANG="$LINKER" ELISA_RUNTIME_OBJ="$OUT/elisacore_runtime.o" \
  "$STAGE1/bin/elisac-stage1" -emit exe -O0 -target-triple "$TRIPLE" \
  -o "$OUT/apk/lib/arm64-v8a/$LIB.so" "$ENTRY"

# --- the Java half -----------------------------------------------------
javac -source 8 -target 8 -nowarn -bootclasspath "$PLATFORM_JAR" -classpath "$PLATFORM_JAR" \
  -d "$OUT/classes" "$ROOT"/src/platform/android/java/org/elisa_ui/*.java 2>&1 |
  grep -v "^warning:" || true
[[ -f "$OUT/classes/org/elisa_ui/ElisaControls.class" ]] || { echo "android controls: javac produced no classes" >&2; exit 2; }
# Run from the class root so the file list is relative: this project's own
# path has a space in it, and an unquoted expansion of absolute names splits.
(cd "$OUT/classes" && find . -name '*.class' | sort > "$OUT/classes.list")
(cd "$OUT/classes" && xargs "$BUILD_TOOLS/d8" --min-api "$API" --output "$OUT" < "$OUT/classes.list")
[[ -f "$OUT/classes.dex" ]] || { echo "android controls: d8 produced no dex" >&2; exit 2; }
cp "$OUT/classes.dex" "$OUT/apk/classes.dex"

# --- the package -------------------------------------------------------
cat > "$OUT/AndroidManifest.xml" <<MANIFEST
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="org.elisa_ui.${EXAMPLE}_controls" android:versionCode="1" android:versionName="1.0">
  <uses-sdk android:minSdkVersion="$API" android:targetSdkVersion="34"/>
  <!-- hasCode is true here and false in the Skia build, which is the whole
       difference between the two backends said in one attribute. -->
  <application android:label="elisa-ui $EXAMPLE controls" android:hasCode="true"
      android:extractNativeLibs="false" android:memtagMode="off" android:debuggable="true"
      android:theme="@android:style/Theme.Material.NoActionBar">
    <activity android:name="org.elisa_ui.ElisaControlsActivity" android:exported="true"
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
"$BUILD_TOOLS/aapt2" link -o "$UNALIGNED" --manifest "$OUT/AndroidManifest.xml" -I "$PLATFORM_JAR"
(cd "$OUT/apk" && zip -q -X "$UNALIGNED" classes.dex && zip -q -0 -X "$UNALIGNED" "lib/arm64-v8a/$LIB.so")
APK="$OUT/$EXAMPLE-controls.apk"
rm -f "$APK"
"$BUILD_TOOLS/zipalign" -P 16 -f 4 "$UNALIGNED" "$APK"
KEYSTORE="${ELISA_UI_ANDROID_KEYSTORE:-$HOME/.android/debug.keystore}"
if [[ ! -f "$KEYSTORE" ]]; then
  mkdir -p "$(dirname -- "$KEYSTORE")"
  keytool -genkeypair -keystore "$KEYSTORE" -storepass android -keypass android -alias androiddebugkey \
    -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi
"$BUILD_TOOLS/apksigner" sign --ks "$KEYSTORE" --ks-pass pass:android --key-pass pass:android \
  --ks-key-alias androiddebugkey "$APK" 2>/dev/null
echo "built $APK"
