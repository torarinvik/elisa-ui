#!/usr/bin/env bash
# Exercise the bounded semantic packet parser without an Android device.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/elisa-android-accessibility.XXXXXX")"
javac -source 8 -target 8 -nowarn -d "$OUT" \
  "$ROOT/src/platform/android/java/org/elisa_ui/ElisaAccessibilitySnapshot.java" \
  "$ROOT/test/android/ElisaAccessibilitySnapshotTest.java"
java -cp "$OUT" org.elisa_ui.ElisaAccessibilitySnapshotTest
