# Google's prebuilt iOS face SDK

The gallery uses Google's MediaPipe Tasks **1.0.1** XCFrameworks for Face
Detector, Face Landmarker and Hand Landmarker on arm64 iOS. Both `VisionDelegate.cpu` and
`VisionDelegate.gpu` work; the latter selects the SDK's Metal delegate. iOS 15
or newer is required. Face blendshapes still use XNNPACK, as configured by
Google's face graph, even when landmark inference uses Metal.

The native-assets hook downloads Google's unchanged Vision, Common, Task
Graphs, Text and Audio archives, verifies their SHA-256 hashes, and links them
with `native/ios/face_sdk_bridge.mm`, `text_sdk_bridge.mm` and
`audio_sdk_bridge.mm`. Xcode compiles only that adapter, which maps the
existing Dart FFI calls to Google's public Objective-C API. Google implements
every task's classes in MediaPipeTasksCommon (the Text and Audio frameworks
carry headers only), so the one adapter also runs the text and audio tasks:
on iOS, `mediapipe_flutter_core.tasks_runtime: true` resolves core's runtime
asset to this framework. It does not
compile MediaPipe, TensorFlow Lite, calculators or inference code from source.
The archive URLs and hashes are pinned in `lib/src/native_assets/ios_sdk.dart`
from [Google's Swift package](https://github.com/google-ai-edge/mediapipe/blob/master/Package.swift).
The graph archive is approximately 1.4 GB; subsequent builds reuse the verified
download. Only the requested device or simulator slice is extracted.

The adapter is the default on iOS devices and the arm64 simulator. For a
consuming app, set its iOS deployment target to 15.0 and list its tasks:

```yaml
hooks:
  user_defines:
    mediapipe_flutter_core:
      tasks_runtime: true # only for the text and audio tasks
    mediapipe_flutter_vision:
      tasks: [face_detector, face_landmarker, hand_landmarker]
```

`official_ios_sdk: false` selects the source-built iOS face runtime (CPU only)
instead; it has no text or audio tasks, so the hook then refuses
`mediapipe_flutter_core.tasks_runtime: true` on iOS. Text and audio on iOS
therefore need `mediapipe_flutter_vision` in the app. The adapter supports the Dart API's
IMAGE and VIDEO modes. Device execution is validated; the hook also selects
the arm64 simulator slice, but simulator GPU execution has not been validated.

Both face asset IDs resolve to one `mediapipe_ios.framework`, so detector and
landmarker can coexist without duplicate calculator registrations. The Dart
worker-isolate API and task options are unchanged. Camera BGRA buffers preserve
their row stride and are copied into `CVPixelBuffer`s without a channel swizzle;
RGB and RGBA inputs are converted to BGRA inside the adapter. The landmarker
reuses Core Video storage through a task-owned pool for BGRA images. Core Video
only reuses released buffers, and the pool is replaced when dimensions change.
This improved unpaced 1080p throughput on the tested iPhone; paced camera-size
latency did not clearly improve. Model bytes use a temporary model file
because the public Objective-C SDK accepts a path. The adapter removes this
file when task creation fails or the task closes.

Prepare and build the gallery:

```sh
python3 tool/prepare.py --target ios/arm64
flutter build ios --release
```

Run the two standalone release validation entrypoints on a physical device:

```sh
flutter build ios --release -t tool/ios_face_sdk_smoke.dart
# Install Runner.app and launch it; exits 0 after CPU/GPU image checks.
flutter build ios --release -t tool/live_face_camera_smoke.dart
# Install Runner.app and launch it; exits 0 after CPU -> GPU -> CPU capture.
```

The first test covers file and pixel inputs, padded RGB/RGBA/BGRA strides,
rotation, optional results, empty detections, video timestamps, disposal,
detector/landmarker coexistence and recovery after invalid model creation.
CPU/GPU landmark differences are recorded, without applying macOS accuracy
tolerances to iOS. File/pixel differences are also recorded because UIKit and
Flutter can decode JPEGs differently. The second test uses the gallery's live
camera controller and verifies twenty frames per delegate selection. Reports
are written to the app's temporary directory as `gallery-ios-sdk-smoke.json`
and `gallery-camera-smoke.json`.
