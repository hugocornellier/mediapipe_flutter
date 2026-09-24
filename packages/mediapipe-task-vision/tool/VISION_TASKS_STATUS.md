# Vision task status

Where each MediaPipe vision task runs, on which delegate, and what proves it.
The capability queries in `lib/capabilities.dart` are the source of truth;
this table restates them for readers and must change in the same commit.
Hand and Face Landmarker have deeper per-platform evidence in
[HAND_LANDMARKER_STATUS.md](HAND_LANDMARKER_STATUS.md) and
[FACE_LANDMARKER_STATUS.md](FACE_LANDMARKER_STATUS.md).

Every target uses Google's official runtime, with no rebuild of MediaPipe
except the macOS face tasks' default archives:

| Target | Runtime |
| --- | --- |
| Web | `@mediapipe/tasks-vision` 1.0.1 JavaScript/WASM through `mediapipe_flutter_vision_web` |
| iOS arm64 and simulator | Google's 1.0.1 XCFrameworks through the official iOS SDK adapter (`official_ios_sdk: true`) |
| Android | `com.google.mediapipe:tasks-vision:1.0.0` through `mediapipe_flutter_vision_android` |
| macOS arm64 | the official 1.0.0 wheel's library (`official_macos_landmark_tasks: true`); the stateful Interactive Segmenter uses core's shared 1.0.1 runtime |
| Linux x64 | the official 1.0.1 wheel's library |
| Windows x64 | the official 1.0.0 wheel's library |

## Support

CPU everywhere a cell has an entry; the entry names the GPU path when there is
one. ✗ means the package refuses the task on that target.

| Task | Web | iOS | Android | macOS | Linux | Windows |
| --- | --- | --- | --- | --- | --- | --- |
| Face Detector | WebGL | Metal | GPU | Metal | GL ES | CPU |
| Face Landmarker | WebGL | Metal | GPU | Metal | GL ES | CPU |
| Hand Landmarker | WebGL | Metal | GPU | Metal | GL ES | CPU |
| Pose Landmarker | WebGL | Metal | GPU | CPU | CPU | CPU |
| Gesture Recognizer | WebGL | Metal | GPU | CPU | CPU | CPU |
| Holistic Landmarker | WebGL | Metal | GPU | CPU | CPU | CPU |
| Object Detector | WebGL | Metal | GPU | Metal | CPU | CPU |
| Image Classifier | WebGL | Metal | GPU | CPU | CPU | CPU |
| Image Embedder | WebGL | Metal | GPU | CPU | CPU | CPU |
| Image Segmenter | WebGL | Metal | GPU | CPU | CPU | CPU |
| Interactive Segmenter Legacy (point) | WebGL | Metal | ✗ [a] | CPU | CPU | CPU |
| Interactive Segmenter (strokes) | WebGL | CPU | CPU | CPU | CPU | ✗ [b] |

Pose and Holistic segmentation masks are returned on every target, with one
Android gap [c]. Android GPU is declared for arm64 devices only: the x86_64
emulator's software GL cannot run it.

## Evidence

- **Web:** in Chrome, every task's output through the Dart adapter is identical
  to Google's JavaScript on the same image, on CPU and WebGL
  (`gallery/tool/browser/test_browser.mjs --suite=api`, both delegates, in CI).
  Firefox runs the CPU suite.
- **iOS:** every task matches Google's references on the arm64 simulator (CPU)
  in CI (`gallery/integration_test/sdk_*_test.dart`). On an iPhone 15 Pro, Face,
  Hand, Pose, Gesture and Holistic Landmarker ran on CPU and Metal, within 0.014
  of each other; the other tasks' Metal paths have not run on a device yet.
- **Android:** every served task matches Google's references on the x86_64
  emulator (CPU) in CI, from the same integration tests. In Firebase Test Lab
  (`integration_test/sdk_all_test.dart`, 27 tests, CPU then GPU), every task
  matched Google's CPU references on a Pixel 8a (Mali), a Galaxy S24 (Adreno)
  and a Galaxy A12 (PowerVR). On GPU, every task matched Google's GPU references
  on the Pixel 8a and the S24, except two Image Segmenter defects in Google's
  GPU path: category values one class low on the S24 (UP-024) and an abort on
  the A12 (UP-023).
  Google's GPU inference differs from its CPU inference for the image-model
  tasks (portrait.jpg's top class scores 0.80 on GPU, 0.31 on CPU, on every GPU
  tried), so GPU results are compared with the wheel's GPU output.
- **macOS:** `tool/test_official_macos_landmark_runtime.py` compares every task
  served by the official runtime with references Google's wheel generates on
  the same Mac, including Metal for Face, Hand and Object Detector. The
  stateful Interactive Segmenter has its own fresh-consumer job.
- **Linux and Windows:** `tool/test_desktop.py` compares every task with
  references the pinned wheel generates on the same runner, then builds and
  runs a Flutter app. Linux GPU matches Google's own GPU output on a CI runner
  whose Mesa renderer is renamed past Google's software-GPU check; a physical
  GPU run is pending ([`test_linux_gpu.sh`](test_linux_gpu.sh)).

## Upstream limits

Details and reproductions are in [upstream-issues.md](../../../upstream-issues.md).

- [a] UP-020: Google's Android 1.0.0 point-based task ignores the keypoint and
  returns the same mask for every point, so the plugin does not serve it.
- [b] Google's Windows wheels do not export the stateful Interactive Segmenter
  API. The Linux wheel does, and the package binds it there.
- [c] UP-018: Google's Android Pose Landmarker throws while converting a mask
  whose width is not a multiple of 4 (for example a rotated 667-pixel image).
  Camera frames are not affected. iOS has the same defect; the adapter repairs
  it.
- UP-023: Google's Android Image Segmenter aborts the app on GPU on a PowerVR
  GPU (Galaxy A12), inside Google's result conversion. CPU works there, and GPU
  matches Google's GPU reference on Mali (Pixel 8a).
- UP-024: Google's Android Image Segmenter category mask is one class low on
  GPU on an Adreno GPU (Galaxy S24): person reads 14, not 15. Confidence masks
  are right, so the most confident class recovers it.
- UP-022: Google's Android stateful Interactive Segmenter drops a model given
  as bytes; the plugin passes it a private file instead. UP-021 is the web
  equivalent for the point-based task.
- UP-025: Google's Windows runtime uploads usage logs to
  `play.googleapis.com`, and closing a task waits for the upload: usually one
  round trip, sometimes 20 to 34 s. CI blocks the host so tests do not depend
  on it.
