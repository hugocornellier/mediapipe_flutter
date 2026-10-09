# Per-family runtimes

Status on 2026-10-07: on `chore/debloat`, for Android, iOS, macOS, Linux and
Windows. With Google's agreement its files are posted unmodified as the
pre-release `per-family-v1.1.0-dev.20261005` on
`hugocornellier/mediapipe_flutter_native`; the hooks download them, and CI and
Firebase Test Lab run them (see [Validated](#validated) and
[Before merging](#before-merging)).
Paths are from the repository root.

## What changed

Each task family bundles Google's MediaPipe C library for that family, so an
app ships only the families it depends on, with no setting:

- **Hooks.** `bundleFamilyRuntime` in
  `packages/mediapipe-core/lib/src/native_assets/family_runtimes.dart` pins
  Google's files by SHA-256 and size, fetches them, and bundles one under
  `package:mediapipe_<family>/mediapipe.dylib`. The vision, text and audio
  hooks call it; core's hook only forwards `asset_source`.
- **Bindings.** Every family binds its own asset. Vision's face tasks bind
  the vision library like every other task, so the face asset aliases and the
  macOS source-built face libraries are gone.
- **macOS.** Google's libraries leave too little header room for the install
  name Dart and Flutter write
  ([UP-042](../../../upstream-issues.md#up-042-per-family-macos-and-simulator-libraries-have-no-header-room-for-a-rename)),
  so the hook names the system frameworks without `Versions/A/` and signs the
  copy again. `tasks_runtime` (the 95 MB opt-in) is gone: vision is 26.6 MB.
- **iOS.** The hook extracts the device or simulator slice from Google's
  XCFramework zip and keeps Google's file name. Core's Objective-C++ adapter
  over the iOS SDK (`native/ios`, about 2,400 lines) is gone, with the
  vision package's BGRA pixel pools and its iOS-only Interactive Segmenter:
  iOS uses the same C API path as macOS. The `official_ios_sdk` setting is
  gone with it.
- **Linux and Windows.** Google's per-family libraries replace the wheel
  libraries. Not run yet.
- **Android.** Each family's hook bundles Google's `.so` for the app's ABIs
  (arm64-v8a, armeabi-v7a and x86_64; no task claims armeabi-v7a), and every
  task calls the C API through FFI, as on iOS and the desktop. The Java
  plugins, core's `TaskHost` library, Google's AARs and their Gradle setup are
  gone, with the `official_android_sdk` setting; the vision plugin only names
  the GPU. The libraries need Android 9: a `minSdk` below 28 fails the build
  with the fix. Model paths reach the C API absolute (`nativeModelPath`),
  since Google's Android resolver reads a relative path as an APK asset.
- **Emulator GPU.** An Android emulator renders OpenGL ES in software
  (SwiftShader), where Google's GPU inference fails, so the vision
  capabilities offer it the CPU only; phones keep the GPU.
- **References.** Every checked-in reference comes from Google's 1.1.0
  release candidate wheel (`mediapipe-nightly` 1.1.0rc20260925), pinned in
  `packages/mediapipe-core/lib/src/native_assets/reference_wheels.dart`,
  which the Dart tests and `tool/official_wheels.py` share. Swap it for the
  1.1.0 wheel once Google publishes it, and regenerate.
- **Text ABI.** The Proofreader and Summarizer options gained a trailing
  `int min_log_severity` in 1.1.0; the Dart structs have it, set to Google's
  default of 4.

## Local builds

`familyRuntimeBaseUrl` points at that pre-release. Google gives several
targets' libraries the same file name (four different
`libmediapipe_tasks_vision.so`), so each release asset is named
`<sha256>-<Google's file name>`; the hook checks its SHA-256 and size and
saves it under Google's name. `hooks.user_defines.mediapipe_core.asset_source`
replaces the release with a directory holding each file under its SHA-256,
for offline builds. That setting covers every pinned download, so the
directory must also hold the models an app bundles. The gallery builder takes
`--asset-source`.

Copies of Google's files keep Firefox's `com.apple.quarantine` flag, and macOS
then refuses to load them; remove it from the copies (`xattr -d`), never from
the originals.

## Validated

On macOS arm64 (M4 Max, macOS 27), against the 1.1.0 references, as
`dart test` counts them:

| Suite | Result |
| --- | --- |
| `mediapipe_core` `dart test` | 55 pass |
| `mediapipe_text` `dart test` | 61 pass |
| `mediapipe_audio` `dart test` | 45 pass |
| `mediapipe_vision` `dart test`, `--tags isolated` | 169 (107 skipped, as before) and 1 pass |
| `mediapipe_text` `--tags modern-text` (EmbeddingGemma, Proofreader, Summarizer; then in `example_embedding`) | 35 pass |
| Gallery: Face Landmarker still image, every vision task's still image, the journey through every page on CPU and Metal | 3 suites pass |

On the arm64 iOS Simulator (iOS 26.4, CPU, as CI runs it), all 12 gallery
suites from `.github/workflows/ios.yaml` pass without core's adapter: every
vision task against Google's references (rotation, padded rows and masks
included), text and audio (the audio stream too), the runtime checks, and the
journey through all 18 pages. Against the 1.1.0 references, EmbeddingGemma's
largest error is 0.0, and Proofreader (9 cases) and Summarizer (10) match
byte for byte.

On an arm64 Android emulator (API 31, CPU), the three gallery suites from
`.github/workflows/android.yaml` pass: `sdk_all_test` (every vision task
against Google's references, rotation and the padded pose mask included, text
and audio with the audio stream, the live tiles, and the journey through
every page), the still image test, and the modern text suite. EmbeddingGemma's
largest error is 0.0, the Proofreader matches in 9 of 9 cases and the
Summarizer in 8 of 10, within the documented rule
([UP-036](../../../upstream-issues.md#up-036-ios-summarizer-generations-drift-from-googles-wheel-late-in-long-summaries)).
Use an API 31 image on Apple silicon: newer ones advertise the M4's SME, which
the hypervisor refuses, so MediaPipe's CPU code stops with SIGILL.

On CI and Firebase Test Lab (October 7, 2026), downloading the libraries
from the release: Linux x64 and Windows x64 pass every CPU job (every vision
task against Google's wheel on the runner, text, audio, the modern text
tasks, the cameras, bundled models and the gallery); the x86_64 Android
emulator passes its three suites and the arm64 iOS Simulator its 12; macOS
passes every job but the GPU memory test on GitHub's virtual Mac
([UP-032](../../../upstream-issues.md#up-032-macos-gpu-tasks-keep-every-frame-until-they-close)).
On Linux's GPU (Mesa), Hand, Gesture and Pose and Image Segmenter's category
mask match Google's GPU wheel exactly. With the GPU required, the Pixel 8a
(Mali) and Galaxy S24 (Adreno) pass all 38 device tests; the Galaxy A12
(PowerVR) passed 37, the 38th expecting the old plugin's error type.

Against the old 1.0.0 references the split libraries failed 17 Face Detector
GPU checks and one text embedding value. Google's own 1.1.0 wheel gives
bit-identical output, so those were 1.1.0 changes (Face Detector's GPU path
moved to LiteRT), not the packaging. The GPU memory test failed only when other
test files shared its process; it now runs alone (`--tags isolated`).

## Before merging

- **Hosting.** Done: the pre-release above. An official URL from Google
  would replace it.
- **Linux and Windows.** Done on CI; see [Validated](#validated).
- **iPhone.** Every iOS suite on a device, with Metal, on the final branch;
  last run on `6c940cf`. The simulator has no GPU path
  ([UP-031](../../../upstream-issues.md#up-031-ios-sdk-gpu-tasks-abort-on-the-ios-simulator)).
- **Android phones.** Done on Test Lab: the Pixel 8a, Galaxy S24 and Galaxy
  A12, GPU required. Face Detector's GPU
  ([UP-046](../../../upstream-issues.md#up-046-face-detectors-gpu-needs-a-litert-plugin-the-linux-and-android-libraries-do-not-ship))
  and Holistic's
  ([UP-026](../../../upstream-issues.md#up-026-holistic-cannot-open-its-face-blendshapes-model-on-a-desktop-or-iphone-gpu))
  are withdrawn on Android, and Image Segmenter's on PowerVR
  ([UP-023](../../../upstream-issues.md#up-023-android-image-segmenter-gpu-aborts-on-a-powervr-gpu)).
  The Adreno off-by-one
  ([UP-024](../../../upstream-issues.md#up-024-android-image-segmenter-gpu-category-mask-is-one-class-low-on-adreno))
  is gone on the C library.
- **Release builds.** A `flutter build ios` and `flutter build macos` release
  of the gallery, and an App Store validation of the iOS frameworks.
- **CI and tools.** The source builds, the macOS engine archive and the
  consumer tools built on them are gone, with their CI jobs. The fresh-app
  harnesses check one pinned library per family, downloaded as an app would;
  `MEDIAPIPE_ASSET_SOURCE` (written into the app's
  `hooks.user_defines.mediapipe_core.asset_source`, see
  `tool/consumer_packages.py`) points them at a local folder instead.
  `tool/mirror_runtime_assets.py --prefill` fills such a folder. `main`'s
  ruleset still requires six checks whose jobs are gone (the macOS landmark
  pin, the public runtime download consumer, the iOS and Android face
  consumers, the separate face GPU comparison and the MagicTouch example
  consumer).
- **Notices.** Google's delivery has no LICENSE or NOTICE; the wheels carry
  both.

## Decision and retrieval

Google's delivery of October 8, 2026 added the `decision` and `retrieval`
families to its per-family libraries, built like the others (LLD on macOS and
the simulator, Apple's ld on iOS devices, Android API 28 with 16 KB pages).

- **Retrieval** (`mediapipe_retrieval`) runs Universal Embedder and Semantic
  Retriever on every target through `familyRuntimes['retrieval']`: Android
  arm64, arm and x86_64; iOS device and simulator; macOS arm64; Linux x64;
  Windows x64; and in browsers on `@mediapipe/tasks-retrieval` 1.1.0. The
  library exports 64 functions, identical on every platform: the two tasks,
  plus the Text and Image Embedder and `MpImage` functions they depend on.
  Google's engine refuses the text-only EmbeddingGemma 2 model for the task
  ([UP-050](../../../upstream-issues.md#up-050-universal-embedder-refuses-the-text-only-embeddinggemma-2-model)),
  so the package pins the text and vision (388 MB) and the full (485 MB)
  models.
- **Decision Maker** (`mediapipe_decision`) runs on the per-family decision
  library through `familyRuntimes['decision']` on Android arm64, arm and
  x86_64, iOS device and simulator, macOS arm64 and Linux x64, and on
  `@mediapipe/tasks-decision` in browsers. The library exports 32 functions
  (the 13 Google's Python declares, plus schema, JSON, context and prewarm
  evaluation); its answers match Google's wheel to float precision with
  Laya and with the text and vision EmbeddingGemma 2, but it fails every
  evaluation with the text-only EmbeddingGemma 2, which the wheel's library
  runs ([UP-053](../../../upstream-issues.md#up-053-the-per-family-decision-library-fails-every-evaluation-with-the-text-only-embeddinggemma-2-model)):
  the package's capability query and `create` say so, and
  `DecisionModels.embeddingGemma2TextVision` is the bi-encoder for it.
  Windows alone stays on the wheel's all-in-one library (`wheelRuntimes`),
  since the delivery has no Windows decision library; Google's C header for
  Decision Maker is still not public. The TODO above `wheelRuntimes` marks
  it.

## Android and iOS rebuilds

The same delivery rebuilt the vision, text and audio libraries for Android and
iOS, and the hooks pin those rebuilds. They export the same functions as the
October 5 builds and add Google's usage-logging client
(`TasksStatsProtoLogger`, with a Clearcut uploader to
`https://play.googleapis.com/log`). The October 5 Android and iOS builds
carried only a logger that does nothing; the desktop libraries, and the
retrieval libraries on every platform, already had the uploader; the decision
libraries have neither (see [privacy and licenses](../../../doc/privacy_and_licenses.md)).
The delivery's macOS and Linux vision, text and audio files are the October 5
bytes, and its Windows ones differ only in their build timestamp, so those
pins stay.

## For Google

- Link the macOS and simulator builds with `-headerpad_max_install_names`
  ([UP-042](../../../upstream-issues.md#up-042-per-family-macos-and-simulator-libraries-have-no-header-room-for-a-rename));
  the October 8 decision and retrieval simulator slices have 32 bytes.
- A Windows decision library, the one target the October 8 delivery lacks,
  and the public C header for Decision Maker.
- The per-family decision library fails every evaluation with the text-only
  EmbeddingGemma 2 model, which the wheel's library runs
  ([UP-053](../../../upstream-issues.md#up-053-the-per-family-decision-library-fails-every-evaluation-with-the-text-only-embeddinggemma-2-model)).
- The families each define the same Objective-C classes
  ([UP-043](../../../upstream-issues.md#up-043-per-family-libraries-each-define-the-same-objective-c-classes)).
- Apple GPU tasks abort on a three-channel image, as Google's 1.0.0 library
  did
  ([UP-044](../../../upstream-issues.md#up-044-apple-gpu-tasks-abort-on-a-three-channel-image-instead-of-failing)).
- The Windows DLLs export TensorFlow Lite and LiteRT
  ([UP-045](../../../upstream-issues.md#up-045-per-family-windows-libraries-export-tensorflow-lite-and-litert)).
- Ship LiteRT's GPU accelerator plugin with the Linux and Android libraries,
  or link it in as on Apple: Face Detector's GPU cannot run without it
  ([UP-046](../../../upstream-issues.md#up-046-face-detectors-gpu-needs-a-litert-plugin-the-linux-and-android-libraries-do-not-ship)).
- OpenGL ES GPU category masks come back as float32 class values, not uint8
  ([UP-047](../../../upstream-issues.md#up-047-opengl-es-gpu-category-masks-come-back-as-float32)).
- On GitHub's virtual Mac, LiteRT cannot create a Metal residency set and
  Face Detector keeps about twice each frame
  ([UP-032](../../../upstream-issues.md#up-032-macos-gpu-tasks-keep-every-frame-until-they-close)).
- A Python wheel from the same build as the libraries, for the references
  ([UP-036](../../../upstream-issues.md#up-036-ios-summarizer-generations-drift-from-googles-wheel-late-in-long-summaries)).
- A LICENSE and NOTICE with the libraries, and an official URL.

## Sizes

Google's per-family libraries as delivered, in MB (10^6 bytes; all
stripped):

| Platform | Vision | Text | Audio | All three | Retrieval |
| --- | --- | --- | --- | --- | --- |
| iOS arm64 (device slice) | 20.0 | 21.2 | 10.0 | 51.2 | 14.0 |
| macOS arm64 | 26.6 | 26.1 | 12.8 | 65.5 | 19.2 |
| Linux x64 | 29.7 | 39.0 | 20.1 | 88.8 | 27.7 |
| Windows x64 | 24.7 | 44.6 | 17.5 | 86.8 | 22.3 |
| Android arm64-v8a | 13.9 | 15.4 | 9.1 | 38.4 | 12.3 |
| Android x86_64 | 16.8 | 18.6 | 11.6 | 46.9 | 15.1 |

The Android arm64-v8a and x86_64 libraries are aligned for 16 KB pages.

Google's 1.1.0 single library (the `mediapipe-nightly` 1.1.0rc20260925
wheels), for comparison: macOS arm64 102.1, Linux x64 88.8 (both stripped)
and Windows x64 57.8. Per family is smaller in every combination on macOS,
equal with all three families on Linux, and larger on Windows whenever text is
combined with another family (62.1 to 86.8). Google prefers per family
everywhere, so the hooks have no per-platform choice.

Downloading native code at run time is not an option on mobile: iOS loads
only code signed into the app bundle (App Store Review Guideline 2.5.2), and
Google Play forbids executable code from outside Play. The choice stays at
build time.
