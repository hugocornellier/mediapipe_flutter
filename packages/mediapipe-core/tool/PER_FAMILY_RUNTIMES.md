# Per-family runtimes

Status on 2026-10-12: every family, on Android, iOS, macOS, Linux and
Windows, pins Google's MediaPipe 1.1.1 development build of October 9, 2026
(see [Google's builds](#googles-builds)). With Google's agreement its files are
posted unmodified as the pre-release `per-family-v1.1.1-dev.20261009` on
`hugocornellier/mediapipe_flutter_native`, beside the earlier builds in
`per-family-v1.1.0-dev.20261005`; the hooks download them, and CI and Firebase
Test Lab run them (see [Validated](#validated) and
[Before merging](#before-merging)). Paths are from the repository root.

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
- **macOS.** The hook bundles Google's dylib as is: since the October 9 build
  it leaves room for the install name Dart and Flutter write. The earlier
  builds did not
  ([UP-042](../../../upstream-issues.md#up-042-per-family-macos-and-simulator-libraries-have-no-header-room-for-a-rename)),
  so the hook used to rename the system frameworks and sign a copy again.
  `tasks_runtime` (the 95 MB opt-in) is gone: vision is 26.3 MB.
- **iOS.** The hook extracts the arm64 binary from Google's framework zip for
  a device or the Simulator (one zip each since October 9; one XCFramework
  before) and keeps Google's file name. Core's Objective-C++ adapter
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

### The October 9 build (1.1.1)

Checked on 2026-10-12 against the same references (the 1.1.0 release
candidate wheel), downloading the libraries from the release:

- **macOS arm64** (M4 Max, macOS 27): core 57, text 96 plus the 35 modern
  text checks, audio 45, Decision Maker 22 (1 skipped), Retrieval 29 and
  every vision task on the CPU pass, as do the text tasks beside the face
  tasks in a debug and a release app. Every CPU output matches the wheel
  exactly, in the package suites and in `tool/test_macos_references.py`.
- **Metal, withdrawn.** Google's 1.1.1 Metal output differs from the
  wheel's for every vision task, on the M4 Max (67 checks of
  `tool/test_macos_references.py`) and on GitHub's runners (68), where the
  October 5 build matched it exactly; the release candidate and the final
  1.1.0 wheel give identical GPU output, and no newer wheel exists. The
  vision package offers the CPU only on macOS until a wheel from the same
  build confirms the new output
  ([UP-057](../../../upstream-issues.md#up-057-the-111-macos-library-gives-different-metal-results-from-googles-110-wheel)).
- **Android arm64 emulator** (API 31, CPU): the gallery's `sdk_all_test`
  (32 checks) and its still image test pass. Its logcat still shows the
  usage-logging client's `Failed to get JNIEnv` error.
- **Android phones** (Firebase Test Lab, GPU required): the Pixel 8a, the
  Galaxy S24 and the Galaxy A12 pass all 38 checks; a first Pixel 8a run
  missed one Image Embedder self-consistency check by 0.000001, and its rerun
  passed. Each phone's logcat shows the `Failed to get JNIEnv` error.
- **iOS Simulator** (arm64, CI): every suite passes.
- **CI** (branches `chore/google-1-1-1-libraries` and `chore/oct12-combined`):
  Linux x64 and Windows x64 on the CPU, Linux's GPU (Mesa) against Google's
  GPU wheel, the x86_64 Android emulator, Decision Maker and Retrieval on
  every platform (WebKit on `macos-26` included), the macOS text and modern
  task jobs, and the bundled models pass. An iPhone is still to report.

### The October 5 and 8 builds (1.1.0)

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
  `tool/mirror_runtime_assets.py --prefill` fills such a folder.
- **Notices.** Since October 9, every family ships Google's LICENSE and
  NOTICE, identical across families; the NOTICE opens with Google's
  MediaPipe Tasks privacy notice. The release posts both, and
  `mediapipe_core` carries them (`third_party/`).

## Decision and retrieval

Google's delivery of October 8, 2026 added the `decision` and `retrieval`
families to its per-family libraries, built like the others (LLD on macOS and
the simulator, Apple's ld on iOS devices, Android API 28 with 16 KB pages).

- **Retrieval** (`mediapipe_retrieval`) runs Universal Embedder and Semantic
  Retriever on every target through `familyRuntimes['retrieval']`: Android
  arm64, arm and x86_64; iOS device and simulator; macOS arm64; Linux x64;
  Windows x64; and in browsers on `@mediapipe/tasks-retrieval` 1.1.0. The
  October 9 library exports 60 functions, identical on every platform: the
  two tasks, the Text and Image Embedder and `MpImage` functions they depend
  on, and the shared error, string list and logging functions.
  Google's engine refuses the text-only EmbeddingGemma 2 model for the task
  ([UP-050](../../../upstream-issues.md#up-050-universal-embedder-refuses-the-text-only-embeddinggemma-2-model)),
  so the package pins the text and vision (388 MB) and the full (485 MB)
  models.
- **Decision Maker** (`mediapipe_decision`) runs on the per-family decision
  library through `familyRuntimes['decision']` on Android arm64, arm and
  x86_64, iOS device and simulator, macOS arm64 and Linux x64, and on
  `@mediapipe/tasks-decision` in browsers. The October 9 library exports 24
  Decision Maker functions (the 13 Google's Python declares, plus schema, JSON,
  context and prewarm evaluation) and the shared helpers; its answers match
  Google's wheel to float precision with
  Laya and with the text and vision EmbeddingGemma 2, but it fails every
  evaluation with the text-only EmbeddingGemma 2, which the wheel's library
  runs ([UP-053](../../../upstream-issues.md#up-053-the-per-family-decision-library-fails-every-evaluation-with-the-text-only-embeddinggemma-2-model)):
  the package's capability query and `create` say so, and
  `DecisionModels.embeddingGemma2TextVision` is the bi-encoder for it.
  Windows alone stays on the wheel's all-in-one library (`wheelRuntimes`),
  since no build has a Windows decision library yet. The TODO above
  `wheelRuntimes` marks it. Google's C header for Decision Maker ships with
  the October 9 build (`packages/mediapipe-core/native/include`), and the
  package's bindings match it.

## Google's builds

| Build | Libraries |
| --- | --- |
| October 5, 2026, 1.1.0 development | vision, text and audio on every target |
| October 8, 2026, 1.1.0 development | retrieval and decision; Android and iOS rebuilds of vision, text and audio |
| October 9, 2026, 1.1.1 development (pinned) | every family on every target |

The October 8 phone rebuilds added Google's usage-logging client
(`TasksStatsProtoLogger`, with a Clearcut uploader to
`https://play.googleapis.com/log`), which the desktop and retrieval libraries
already had; the October 5 phone libraries had only a logger that does
nothing, and the October 8 decision libraries had no logger.

The October 9 build (its `BUILD_INFO` is in `packages/mediapipe-core/native`):

- **Header room.** Its macOS dylibs and iOS slices leave 15 to 28 KB, so the
  hook bundles them as is
  ([UP-042](../../../upstream-issues.md#up-042-per-family-macos-and-simulator-libraries-have-no-header-room-for-a-rename)).
- **iOS packaging.** One framework zip for devices and one for the Simulator,
  instead of an XCFramework; the Simulator binary still holds arm64 and
  x86_64.
- **Logging callback.** Every library exports `MpSetLoggingCallback` and
  `MpRemoveLoggingCallback` (`core/mp_logging.h`); see
  [RUNTIME_LOGS.md](RUNTIME_LOGS.md). The six `MpFlatbuffer*` functions are
  gone, though `metadata/flatbuffer_api.h` still declares them.
- **Host environment.** `MpBaseOptions` accepts `MP_HOST_ENVIRONMENT_FLUTTER`
  (5), with the same layout; see [Flutter host
  environment](#flutter-host-environment).
- **Usage logging everywhere.** Every library has the usage-logging client,
  the decision libraries too, which roughly doubles them. On Android the
  client reaches the network through Java, and in an app that loads the
  library through FFI it cannot: Test Lab's logcats of the October 8 build
  show `Failed to get JNIEnv in AndroidNetworkManager::OnAttachedToJvm()`,
  and the October 9 library still has no `JNI_OnLoad` or Java VM setter (see
  [privacy and licenses](../../../doc/privacy_and_licenses.md)).
- **Headers and notices.** Each family ships its C headers, now vendored in
  `packages/mediapipe-core/native/include`, with Google's LICENSE, NOTICE
  and BUILD_INFO.
- **GPU output.** On macOS, Metal output differs from the 1.1.0 wheel's for
  every vision task, so the vision package withdraws the macOS GPU: see
  [Validated](#validated).
- Still no Windows decision library. Linux arm64, Windows arm64 and Android
  x86 libraries come too; no task claims them, so the release does not post
  them.

## Flutter host environment

Planned, not started. Google's libraries record each task's host environment
and OS in their usage log, from `MpBaseOptions.host_environment` and
`host_system`. The packages fill only `host_system` (`mpHostSystem` in
`packages/mediapipe-core/lib/src/host_io.dart`), and with `host_environment`
left at 0 the library records the OS as unknown too, so a Flutter app's
uploads carry neither; Google's Python sends PYTHON and its OS (checked on
2026-10-08). The October 9 build adds `MP_HOST_ENVIRONMENT_FLUTTER` (5) for
this.

- Set `host_environment` to 5 in core, next to `host_system`, for every
  family's native options, and consider `host_version` (the Flutter or Dart
  version).
- Not for Decision Maker on Windows while it runs the 1.1.0 wheel's library,
  which predates the value: its conversion logs an unknown value at
  `DFATAL`, which aborts debug builds of Google's code.
- Browsers need nothing: Google's JavaScript runtime sets its own
  environment.
- Check it with a local receiver for the uploads, as the telemetry check did:
  each upload should name FLUTTER and the OS.

## For Google

- A Windows decision library, the one target the October 9 build still
  lacks.
- Headers for the Proofreader, Summarizer and Interactive Segmenter, which
  the libraries export; `metadata/flatbuffer_api.h` declares functions none
  of them exports.
- If Google wants usage logs from Android apps that load the libraries
  through FFI: a way to hand the uploader the Java VM (an exported setter or
  `JNI_OnLoad`), or a native HTTP path.
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
  ([UP-036](../../../upstream-issues.md#up-036-ios-summarizer-generations-drift-from-googles-wheel-late-in-long-summaries)),
  and to show whether the 1.1.1 build's different Metal output is intended
  ([UP-057](../../../upstream-issues.md#up-057-the-111-macos-library-gives-different-metal-results-from-googles-110-wheel)).
  `mediapipe-nightly` stops at 1.1.0rc20260925, though npm has had 1.1.1
  nightlies since October 8.
- An official URL.

## Sizes

Google's per-family libraries of the October 9 build, in MB (10^6 bytes;
all stripped):

| Platform | Vision | Text | Audio | All three | Retrieval | Decision |
| --- | --- | --- | --- | --- | --- | --- |
| iOS arm64 (device binary) | 19.8 | 20.2 | 9.8 | 49.8 | 13.9 | 12.6 |
| macOS arm64 | 26.3 | 25.0 | 12.6 | 63.9 | 19.0 | 16.5 |
| Linux x64 | 29.4 | 38.2 | 19.8 | 87.4 | 27.5 | 32.1 |
| Windows x64 | 24.1 | 37.4 | 17.0 | 78.5 | 21.8 | none |
| Android arm64-v8a | 13.4 | 14.6 | 8.8 | 36.8 | 12.0 | 15.1 |
| Android x86_64 | 16.6 | 18.0 | 11.4 | 46.0 | 15.0 | 18.5 |

The Android arm64-v8a and x86_64 libraries are aligned for 16 KB pages.

Google's 1.1.0 single library (the `mediapipe-nightly` 1.1.0rc20260925
wheels), for comparison: macOS arm64 102.1, Linux x64 88.8 (both stripped)
and Windows x64 57.8. Per family is smaller in every combination on macOS
and Linux, and larger on Windows when text is combined with vision (61.5) or
with both others (78.5). Google prefers per family everywhere, so the hooks
have no per-platform choice.

Downloading native code at run time is not an option on mobile: iOS loads
only code signed into the app bundle (App Store Review Guideline 2.5.2), and
Google Play forbids executable code from outside Play. The choice stays at
build time.
