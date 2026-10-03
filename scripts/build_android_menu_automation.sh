#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
BUILD_TOOLS="${ANDROID_BUILD_TOOLS:-$(ls -d "$SDK"/build-tools/* | sort -V | tail -1)}"
PLATFORM_JAR="${ANDROID_PLATFORM_JAR:-$(ls "$SDK"/platforms/*/android.jar | sort -V | tail -1)}"
OUT="$ROOT/build/android-menu-automation"
mkdir -p "$OUT/classes"
javac -source 8 -target 8 -nowarn -bootclasspath "$PLATFORM_JAR" -classpath "$PLATFORM_JAR" \
  -d "$OUT/classes" "$ROOT/test/android/ElisaMenuAutomation.java"
"$BUILD_TOOLS/d8" --min-api 30 --output "$OUT" "$OUT/classes/org/elisa_ui/menucheck/ElisaMenuAutomation.class"
"$BUILD_TOOLS/aapt2" link -o "$OUT/unaligned.apk" --manifest "$ROOT/test/android/menu-automation-manifest.xml" -I "$PLATFORM_JAR"
(cd "$OUT" && zip -q -X unaligned.apk classes.dex)
"$BUILD_TOOLS/zipalign" -f 4 "$OUT/unaligned.apk" "$OUT/menu-automation.apk"
KEYSTORE="${ELISA_UI_ANDROID_KEYSTORE:-$HOME/.android/debug.keystore}"
"$BUILD_TOOLS/apksigner" sign --ks "$KEYSTORE" --ks-pass pass:android --key-pass pass:android \
  --ks-key-alias androiddebugkey "$OUT/menu-automation.apk"
echo "built $OUT/menu-automation.apk"
