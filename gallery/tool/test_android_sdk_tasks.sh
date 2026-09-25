#!/usr/bin/env bash
# Runs the official Android SDK task tests on an emulator, CPU only: Hand
# Landmarker; Pose, Gesture and Holistic; Face and Object Detector and Image
# Classifier; Image Embedder; Image Segmenter; then every live tile in one
# process.
#
# The emulator's SwiftShader GL accepts a GPU task, then TFLite's GL delegate
# fails on the first frame, so GPU stays a phone check. `flutter test`
# installs the app itself, so camera permission is granted while it runs;
# otherwise the live demo waits behind the permission prompt and gets no
# frames. Firebase Test Lab grants it the same way before launch.
set -euo pipefail
device=${1:?usage: test_android_sdk_tasks.sh <device>}
cd "$(dirname "$0")/.."
(
  while true; do
    adb -s "$device" shell pm grant com.example.mediapipe_gallery \
      android.permission.CAMERA >/dev/null 2>&1 || true
    sleep 1
  done
) &
granter=$!
trap 'kill $granter 2>/dev/null || true' EXIT
log=$(mktemp)
for test in sdk_hand_landmarker_test sdk_landmark_tasks_test sdk_detection_tasks_test \
    sdk_embedder_test sdk_segmenter_test sdk_interactive_segmenter_test runtime_test; do
  for attempt in 1 2; do
    # A file takes under 6 minutes with the first Gradle build. On hosted
    # emulators flutter test sometimes installs the app and then hears
    # nothing more, so a file still running at 10 minutes has stalled.
    status=0
    timeout 600 flutter test -d "$device" "integration_test/$test.dart" \
        --dart-define=SDK_GPU=skip --reporter expanded 2>&1 | tee "$log" || status=$?
    [ "$status" = 0 ] && break
    if [ "$status" = 124 ]; then
      echo "$test stalled; the emulator's log follows"
      adb -s "$device" logcat -d -t 300 || true
    fi
    # On hosted emulators flutter test sometimes cannot start the Dart
    # Development Service; no test ran, so the file runs once more.
    if [ "$attempt" = 1 ] && { [ "$status" = 124 ] ||
        grep -q "Failed to start Dart Development Service" "$log"; }; then
      echo "Retrying $test"
      continue
    fi
    exit 1
  done
done
