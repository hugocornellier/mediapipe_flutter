# Vision task status

Where each MediaPipe vision task runs, on which delegate, and what proves it.
The capability queries in `lib/src/capabilities.dart` are the source of truth;
this table restates them for readers and must change in the same commit.
Hand and Face Landmarker's deeper per-platform evidence pages,
`HAND_LANDMARKER_STATUS.md` and `FACE_LANDMARKER_STATUS.md`, are in git history
at `9383185`.

Every target uses Google's official runtime, with no rebuild of MediaPipe:

| Target | Runtime |
| --- | --- |
| Web | `@mediapipe/tasks-vision` 1.0.1 JavaScript/WASM through `mediapipe_vision` |
| iOS arm64 and simulator | Google's 1.1.0 vision library (`MediaPipeTasksVisionC`), which this package's hook bundles |
| Android arm64 and x86_64 | Google's 1.1.0 vision library (`libmediapipe_tasks_vision.so`), which this package's hook bundles |
| macOS arm64 | Google's 1.1.0 vision library (`libmediapipe_tasks_vision`) |
| Linux x64 | Google's 1.1.0 vision library (not yet run in CI) |
| Windows x64 | Google's 1.1.0 vision library (not yet run in CI) |

## Support

CPU everywhere a cell has an entry; the entry names the GPU path when there is
one. ✗ means the package refuses the task on that target.

| Task | Web | iOS | Android | macOS | Linux | Windows |
| --- | --- | --- | --- | --- | --- | --- |
| Face Detector | WebGL | Metal | GPU | Metal | GL ES | CPU |
| Face Landmarker | WebGL | Metal | GPU | Metal | GL ES | CPU |
| Hand Landmarker | WebGL | Metal | GPU | Metal | GL ES | CPU |
| Pose Landmarker | WebGL | Metal | GPU | Metal [d] | GL ES [d] | CPU |
| Gesture Recognizer | WebGL | Metal | GPU | Metal | GL ES | CPU |
| Holistic Landmarker | WebGL | CPU [e] | GPU | CPU [e] | CPU [e] | CPU |
| Object Detector | WebGL | Metal | GPU | Metal | GL ES | CPU |
| Image Classifier | WebGL | Metal | GPU | Metal | GL ES | CPU |
| Image Embedder | WebGL | Metal | GPU | Metal | CPU [f] | CPU |
| Image Segmenter | WebGL | Metal | GPU | Metal | GL ES | CPU |
| Interactive Segmenter (strokes) | WebGL | CPU | CPU | CPU [g] | CPU [g] | ✗ [b] |

Pose and Holistic segmentation masks are returned on every target. Android
GPU is declared for arm64 devices only, and withdrawn on any emulator, whose
OpenGL ES is software (SwiftShader).

## Evidence

- **Web:** in Chrome, every task's output through the Dart adapter is identical
  to Google's JavaScript on the same image, on CPU and WebGL
  (`gallery/tool/browser/test_browser.mjs --suite=api`, both delegates, in CI).
  Firefox and WebKit run the CPU suite, WebKit on macOS: Linux WebKit builds
  give a worker's OffscreenCanvas no WebGL context, which Google's vision tasks
  need even on CPU.
- **iOS:** every task matches Google's references on the arm64 simulator (CPU)
  in CI (`gallery/integration_test/sdk_*_test.dart`). On an iPhone 15 Pro, Face,
  Hand, Pose, Gesture and Holistic Landmarker ran on CPU and Metal, within 0.014
  of each other; the other tasks' Metal paths have not run on a device yet.
- **Android:** on Google's 1.1.0 vision library, every task matches Google's
  references on an arm64 emulator (API 31, CPU), from the same integration
  tests, rotation and the padded pose mask included; CI's x86_64 emulator and
  Firebase Test Lab's phones wait until Google publishes the library. Earlier,
  on Google's Java SDK (tasks-vision 1.0.0), every task matched on the CI
  emulator and in Firebase Test Lab (`integration_test/sdk_all_test.dart`, 27
  tests, CPU then GPU): Google's CPU references on a Pixel 8a (Mali), a Galaxy
  S24 (Adreno) and a Galaxy A12 (PowerVR), and its GPU references on the
  Pixel 8a and the S24, except two Image Segmenter defects in that SDK's GPU
  path: category values one class low on the S24 (UP-024) and an abort on
  the A12 (UP-023).
  Google's GPU inference differs from its CPU inference for the image-model
  tasks (portrait.jpg's top class scores 0.80 on GPU, 0.31 on CPU, on every GPU
  tried), so GPU results are compared with the wheel's GPU output.
- **macOS:** the package tests compare every task with references from
  Google's 1.1.0 wheel on the same Mac, including Metal for Face, Hand, Pose
  (landmarks), Gesture, Object Detector, Image Classifier, Image Embedder and
  Image Segmenter (IMAGE mode).
- **Linux and Windows:** `tool/test_desktop.py` compares every task with
  references the pinned wheel generates on the same runner, then builds and
  runs a Flutter app. Linux GPU (Face, Hand, Pose, Gesture, Object Detector,
  Image Classifier and Image Segmenter) matches Google's own GPU output on a CI
  runner whose Mesa renderer is renamed past Google's software-GPU check
  (`tool/prepare_gpu_reference.py --test`); a physical GPU run is pending.

## Upstream limits

Details and reproductions are in [upstream-issues.md](../../../upstream-issues.md).

- [b] Google's Windows library does not export the stateful Interactive
  Segmenter API. The Linux, macOS and iOS ones do, and the package binds it
  there.
- [d] UP-028 and UP-030: Google's desktop GPU paths give no float Pose masks
  (Metal fails; OpenGL ES returns 8-bit RGBA images), so the package refuses
  masks on those GPUs with the reason; landmarks run, and masks run on CPU.
- [e] UP-026: neither desktop runtime nor Google's iOS library opens
  Holistic's face blendshapes model on the GPU delegate.
- [f] UP-027: Google's Linux runtime aborts the Image Embedder on OpenGL ES.
- [g] UP-008 and UP-029: the stroke segmenter's GPU path fails on macOS and
  aborts on Linux.
- UP-023: Google's Android Java SDK aborted the app in its Image Segmenter
  on a PowerVR GPU (Galaxy A12, Pixel 10, Pixel 11), inside its result
  conversion. CPU works there, and GPU matched Google's GPU reference on Mali
  (Pixel 8a). Its C library has not run on a PowerVR GPU yet, so the package
  still withdraws that task's GPU on PowerVR, named by the vision plugin.
- UP-024: the same SDK's Image Segmenter category mask was one class low on
  GPU on an Adreno GPU (Galaxy S24): person read 14, not 15. Confidence masks
  were right, so the most confident class recovers it. Its C library has not
  run on an Adreno GPU yet.
- UP-025: Google's Windows runtime uploads usage logs to
  `play.googleapis.com`, and closing a task waits for the upload: usually one
  round trip, sometimes 20 to 34 s. CI blocks the host so tests do not depend
  on it.
