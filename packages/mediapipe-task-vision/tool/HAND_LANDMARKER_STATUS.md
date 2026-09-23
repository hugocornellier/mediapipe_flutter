# Hand Landmarker status

Where Hand Landmarker runs, on which delegate, and what proves it. The columns
match [the Face Landmarker table](FACE_LANDMARKER_STATUS.md). Update this file
in the same commit as the evidence.

Every target uses Google's official runtime, with no rebuild of MediaPipe:

| Target | Runtime |
| --- | --- |
| Web | `@mediapipe/tasks-vision` 1.0.1 JavaScript/WASM through `mediapipe_flutter_vision_web` |
| macOS arm64 | the official 1.0.0 wheel's library (the gallery's opt-in official runtime) |
| iOS arm64 and simulator | Google's 1.0.1 XCFrameworks through `native/ios/face_sdk_bridge.mm` |
| Android | `com.google.mediapipe:tasks-vision:1.0.0` through `mediapipe_flutter_vision_android` |
| Linux x64 | the official 1.0.1 wheel's library (CPU and GPU) |
| Windows x64 | the official 1.0.0 wheel's library (CPU only) |

Symbols: ✅ recorded, ⚠️ partial (see note), ❌ nothing recorded, 🧑 needs a
person or a device that hosted CI cannot provide.

| Platform | Reference | Lifecycle | Injected pipeline | Real capture | Hand in view | GPU |
| --- | --- | --- | --- | --- | --- | --- |
| Web (Chrome) | ✅ CPU + GPU, matches Google's JavaScript [1] | ✅ [1] | ✅ file-backed webcam in CI [1] | ✅ CI fake device [1] | ✅ fixture hand through the fake webcam, overlay oracle [1] | ✅ WebGL 2 [1] |
| Web (Firefox) | ✅ CPU [1] | ✅ [1] | ❌ | ❌ | ❌ | ❌ |
| macOS arm64 | ✅ CPU + Metal, same as Google's wheel [2] | ✅ [2] | ✅ | ❌ | ❌ | ✅ Metal [2] |
| iOS simulator | ✅ CPU, max delta 0.004 [3] | ✅ VIDEO tracking, blank frames [3] | ❌ | 🧑 no simulator camera | 🧑 | 🧑 Google's SDK aborts in Metal preprocessing on the simulator |
| iOS arm64 (device) | 🧑 | 🧑 | 🧑 | 🧑 | 🧑 | 🧑 |
| Android emulator | ✅ CPU, max delta 0.0005 [4] | ✅ VIDEO tracking, blank frames [4] | ❌ | ⚠️ emulator scene camera, 11+ frames processed [4] | ❌ | 🧑 SwiftShader GL fails on the first frame |
| Android arm64 (device) | 🧑 | 🧑 | 🧑 | 🧑 | 🧑 | 🧑 |
| Linux x64 | ✅ CPU [5] | ✅ [5] | ✅ supplied frames [5] | ❌ | ❌ | ⚠️ renamed llvmpipe in CI, first run pending [6] |
| Windows x64 | ✅ CPU [5] | ✅ [5] | ✅ supplied frames [5] | ❌ | ❌ | n/a, no GPU runtime |

"Reference" deltas are the largest per-coordinate difference from Google's
official CPU landmarks for `thumb_up.jpg`
(`test/fixtures/landmark_tasks/official_reference.json`, generated on macOS
with the Python wheel). Different platforms' runtimes differ by that much;
same-runtime comparisons (web against Google's JavaScript, macOS against
Google's wheel) are exact.

Opening Face Landmarker and then Hand Landmarker in one app is covered by
`gallery/integration_test/runtime_test.dart` on macOS, Linux, Windows and the
iOS simulator. On macOS it guards the fix that loads Google's runtime once per
process.

## Records

1. The Web workflow: `gallery/tool/browser/test_browser.mjs --suite=camera --task=hand`,
   and the API suite's hand comparison in Chrome and Firefox.
2. The macOS workflow's official landmark runtime job, and the physical-Mac
   Metal reference in `test/fixtures/landmark_tasks/official_gpu_reference.json`
   (M4 Max, official 1.0.0 wheel).
3. The iOS workflow's `hand-sdk` job:
   `gallery/integration_test/sdk_hand_landmarker_test.dart` with `SDK_GPU=skip`.
   First run locally on an iPhone 17 Pro simulator, 2026-09-23.
4. The Android workflow's `hand-sdk` job: `gallery/tool/test_android_hand.sh`.
   First run locally on an API 31 arm64 emulator, 2026-09-23.
5. The Desktop workflow: `tool/test_desktop.py --landmark-tasks` and the
   gallery's `desktop_cpu_camera_test.dart` with `GALLERY_LIVE_TASK=hand`.
6. The Desktop workflow's Linux GPU job, `desktop_gpu_camera_test.dart` with
   `GALLERY_LIVE_TASK=hand`. Not yet run on a physical Linux GPU.

## Filling the 🧑 cells

**iOS device.** The same test runs on a phone, where GPU must work:

```sh
python3 -B gallery/tool/prepare.py --target ios/arm64 --tasks hand_landmarker
cd gallery && flutter pub get
flutter test -d <iphone-id> integration_test/sdk_hand_landmarker_test.dart \
  --dart-define=SDK_GPU=required --reporter expanded
```

**Android device.** Grant camera permission and run the same test with
`SDK_GPU=required`, on a phone or in Firebase Test Lab
(see `gallery/tool/ANDROID_FACE_TESTLAB.md` for the Test Lab route):

```sh
python3 -B gallery/tool/prepare.py --target android/arm64 --tasks hand_landmarker
cd gallery && flutter pub get
flutter test -d <device-id> integration_test/sdk_hand_landmarker_test.dart \
  --dart-define=SDK_GPU=required --reporter expanded
```

Both runs print `SDK_HAND_LANDMARKER` lines with the reference delta, the
CPU/GPU delta and the live gallery frame count. Record them here.
