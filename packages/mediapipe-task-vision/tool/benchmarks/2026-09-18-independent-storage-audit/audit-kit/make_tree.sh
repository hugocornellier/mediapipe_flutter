#!/bin/bash
# Create an isolated source tree for one flavor without touching the working tree.
#   make_tree.sh <dest> <base|cand> <ios|macos>
# base: the three storage files replaced by the pre-change sources archived in
#       raw-results.tar.gz (sources/baseline), hash-checked.
# cand: the current working-tree sources (production default: pool, mode 2).
set -euo pipefail
KIT=$(cd "$(dirname "$0")" && pwd)
REPO=$KIT
until [ -f "$REPO/.mediapipe_flutter-root" ]; do
  REPO=$(dirname "$REPO")
  [ "$REPO" = / ] && { echo "repository marker not found" >&2; exit 1; }
done
BASELINE=${BASELINE_SOURCES:-$KIT/../sources/baseline}
DEST=$1 FLAVOR=$2 PLATFORM=$3
[ -e "$DEST" ] && { echo "refusing to overwrite $DEST" >&2; exit 1; }
mkdir -p "$DEST/packages"
cp "$REPO/.mediapipe_flutter-root" "$DEST/"
cp "$REPO/packages/analysis_options.yaml" "$DEST/packages/"
for p in mediapipe-core mediapipe-task-vision; do
  rsync -a --exclude /build --exclude /.dart_tool --exclude /models \
    --exclude /example --exclude /example_segmenter --exclude /test \
    "$REPO/packages/$p/" "$DEST/packages/$p/"
done
rsync -a --exclude /build --exclude /.dart_tool --exclude /.idea --exclude /pubspec.lock \
  "$REPO/gallery/" "$DEST/gallery/"
V=$DEST/packages/mediapipe-task-vision
check() { [ "$(shasum -a 256 "$1" | cut -d' ' -f1)" = "$2" ] || { echo "hash mismatch: $1" >&2; exit 1; }; }
if [ "$FLAVOR" = base ]; then
  cp "$BASELINE/face_sdk_bridge.mm" "$V/native/ios/face_sdk_bridge.mm"
  cp "$BASELINE/native_ios_sdk.dart" "$V/lib/src/io/native_ios_sdk.dart"
  cp "$BASELINE/native_face_landmarker.dart" "$V/lib/src/io/native_face_landmarker.dart"
  check "$V/native/ios/face_sdk_bridge.mm" 5c966a49c1f793129581a84ff66b132ccc2cc732ab5230b0647d2a6cd5ad4c3a
  check "$V/lib/src/io/native_ios_sdk.dart" 12f792a088dc206a2919efce030494469699353d644035d1f9ac109977ded0b0
  check "$V/lib/src/io/native_face_landmarker.dart" bb9b65cc307e147d0da3cacae989def83a4a6fa24a0a96f2b0ebdaab41eef80a
else
  check "$V/native/ios/face_sdk_bridge.mm" 87fca1b7f97dc185f3751d421287d33d781ac953ccb66abd83eaaaa59bce1013
  check "$V/lib/src/io/native_ios_sdk.dart" dee4642c8bdb6b314a271a5e75c1612007a65bc90edbdaf0a95105bc3c2f783c
  check "$V/lib/src/io/native_face_landmarker.dart" 5c8ec1c59b245ffa1866360da64fe8bb3ffe96060e05ac491ae0355c88203d6a
fi
G=$DEST/gallery
cp "$KIT/storage_audit_benchmark.dart" "$G/tool/"
mkdir -p "$G/assets/bench"
cp "$KIT"/assets/*.bin "$G/assets/bench/"
if [ "$PLATFORM" = ios ]; then
  cp "$KIT/overlay/ios/AppDelegate.swift" "$G/ios/Runner/AppDelegate.swift"
  python3 - "$G/pubspec.yaml" <<'EOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); t = p.read_text()
anchor = '    - assets/manifest.json\n'
assert anchor in t and 'assets/bench' not in t
p.write_text(t.replace(anchor, anchor + '    - assets/bench/portrait_480x640_bgra.bin\n'
                       '    - assets/bench/portrait_1080x1920_bgra.bin\n'))
EOF
  SDK=gallery/.dart_tool/hooks_runner/shared/mediapipe_flutter_vision/build/official-ios-sdk
  mkdir -p "$(dirname "$DEST/$SDK")"
  cp -cR "$REPO/$SDK" "$DEST/$SDK"
else
  cp "$KIT/overlay/macos/MainFlutterWindow.swift" "$G/macos/Runner/MainFlutterWindow.swift"
  mkdir -p "$V/build/native"
  cp -cR "$REPO/packages/mediapipe-task-vision/build/native/official-macos-landmarks" "$V/build/native/"
  cat > "$G/pubspec.yaml" <<'EOF'
# Storage-audit harness only: the gallery's macOS face runtime (Google's
# official 1.0.0 monolith), without camera plugins or other tasks.
name: mediapipe_gallery
publish_to: none
version: 0.1.0+1

environment:
  sdk: ^3.12.0

dependencies:
  flutter:
    sdk: flutter
  mediapipe_flutter_vision:
    path: ../packages/mediapipe-task-vision

dev_dependencies:
  crypto: ^3.0.6

hooks:
  user_defines:
    mediapipe_flutter_vision:
      official_macos_landmark_tasks: true
      tasks: [face_landmarker]

flutter:
  uses-material-design: true
  assets:
    - assets/models/face_landmarker.task
    - assets/bench/portrait_480x640_bgra.bin
    - assets/bench/portrait_1080x1920_bgra.bin
EOF
fi
echo "tree ready: $DEST ($FLAVOR, $PLATFORM)"
