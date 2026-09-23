# iPhone official SDK landmark tasks, 2026-09-23

Device: iPhone 15 Pro (iPhone16,1), iOS 27.0, USB. Google's 1.0.1 iOS
XCFrameworks through `native/ios/face_sdk_bridge.mm`, the gallery's
test app, `--dart-define=SDK_GPU=required` (a GPU refusal fails the run).

| Task | CPU vs Google | Metal vs Google | Rotated, CPU | CPU vs Metal |
| --- | --- | --- | --- | --- |
| Hand | 0.0045 | 0.0062 | n/a | 0.014 |
| Pose | 0.0015 | 0.0110 | 0.012 | 0.014 |
| Gesture (Thumb_Up) | 0.0045 | 0.0062 | 0.005 | 0.014 |
| Holistic | 0.0015 | 0.0110 | 0.008 | 0.014 |

"vs Google" is the largest x or y difference from Google's CPU landmarks from
the official 1.0.0 macOS wheel (`test/fixtures/landmark_tasks/`). Pose's Metal
result on the rotated input is 0.22 from the CPU reference; Google's own wheel
shows the same split (upstream-issues.md UP-015). The hand run also opened the
live gallery on the real camera: 12 frames processed, 4 cameras found.

Reproduce:

```sh
python3 -B gallery/tool/prepare.py --target ios/arm64
cd gallery && flutter pub get
flutter test -d <iphone-id> --dart-define=SDK_GPU=required \
  integration_test/sdk_hand_landmarker_test.dart
flutter test -d <iphone-id> --dart-define=SDK_GPU=required \
  integration_test/sdk_landmark_tasks_test.dart
```

`flutter test` does not run on a phone connected over Wi-Fi; use a cable.
