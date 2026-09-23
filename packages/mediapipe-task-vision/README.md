# mediapipe_flutter_vision

Official MediaPipe Face Detector and Face Landmarker for Dart and Flutter on **macOS arm64**.
This development version implements **CPU and Metal GPU IMAGE/VIDEO modes**. It accepts JPEG/image
files or RGB/RGBA/BGRA pixels and returns face boxes, categories, and
six keypoints, or all 478 facial landmarks including irises. Inference runs on
a worker isolate. Face Landmarker also exposes the official optional 52
blendshape scores and 4×4 face transformation matrices.

An **arm64 iOS simulator CPU** development target is also available, using the
same Dart API and official task graphs. It currently requires a local native
build; simulator archives are not published. The opt-in
[official iOS SDK adapter](tool/IOS_OFFICIAL_SDK.md) also provides CPU/Metal
face tasks, including physical-device camera validation. See
[the simulator guide](tool/IOS_SIMULATOR.md) for the source-built CPU path.

CI builds the iOS simulator face runtime from pinned source and tests a fresh
Flutter consumer. Android face CI builds x86_64 from source and tests an emulator
with debug/release APKs. That source-built path requires a verified local native
build; see [the Android guide](tool/ANDROID.md). Flutter FaceLandmarker apps can
instead use the [official Android SDK plugin](../mediapipe-task-vision-android/README.md),
which provides CPU/GPU IMAGE/VIDEO inference without a local C++ build.
The physical Pixel 7 / Android 13 Test Lab campaign validates both delegates,
including front/back camera frames and delegate switching; see
[the Test Lab guide](../../gallery/tool/ANDROID_FACE_TESTLAB.md).

**All twelve vision tasks** run through Google's official runtimes on web, iOS,
Android, macOS, Linux and Windows, with two exceptions caused by Google's
runtimes. [The status table](tool/VISION_TASKS_STATUS.md) lists each task's
targets and GPU paths, the evidence behind them, and those upstream limits.

**Hand Landmarker** runs on every target through Google's official runtimes:
the Linux and Windows wheels, the opt-in macOS runtime, the iOS SDK adapter,
and the Android and web adapter packages. GPU is available everywhere except
Windows. See [its status matrix](tool/HAND_LANDMARKER_STATUS.md) for what each
platform's evidence covers.

**MagicTouch Interactive Segmenter** uses Google's modern stateful 1.0.1 API
and official int8 version-1 task bundle. It selects arbitrary objects from
positive, negative and lasso strokes, on CPU, on macOS arm64 (macOS 14 or
newer), Linux x64, iOS, Android and the web. Google's Windows runtime does not
include it. See [the segmenter guide](tool/INTERACTIVE_SEGMENTER.md) for the API,
model, packaging and validation details. Run `make example_segmenter` from the
repository root for the macOS image editor; the gallery has the same editor on
every supported target.

On macOS, MagicTouch apps must also enable
`hooks.user_defines.mediapipe_flutter_core.tasks_runtime: true`. Core bundles the
official 1.0.1 library once, shared with EmbeddingGemma when both tasks are used.
Existing segmenter apps should add this setting and run `flutter clean` after
updating, so an earlier task-owned framework is removed from the app bundle.

The task uses the unmodified MediaPipe v1.0.0 Face Detector graph and its official
BlazeFace short-range float16 model, version 1. MediaPipe performs image
preprocessing, model inference, anchor decoding, suppression, and coordinate
projection. Face Landmarker uses Google's complete float16 version-1 bundle,
including its own detector, landmark model, and expression model.
It does not require a separate Dart Face Detector call. The Dart wrapper copies
results and owns native resource cleanup.

On macOS, Face Landmarker remains on the **1.0.0 runtime**. Runtime and model versions are
independent: Google's latest Face Landmarker model bundle was verified identical
to our pinned version-1 bundle on September 14, 2026. The official 1.0.1 macOS
runtime aborts during CPU task creation, so it cannot replace the working runtime
yet. See [the compatibility check](tool/validations/2026-09-14-face-landmarker-1.0.1/README.md)
and [upstream issue #6356](https://github.com/google-ai-edge/mediapipe/issues/6356).

## Linux and Windows

On Linux x64 and Windows x64 the build hook downloads the native library from
Google's official PyPI wheel, then extracts it and verifies it by digest:
`mediapipe==1.0.1` on Linux (the first Linux wheel built with GPU) and
`mediapipe==1.0.0` on Windows. Both run every vision task on CPU, except the
stateful Interactive Segmenter on Windows, whose wheel does not export it.

The Linux runtime links the system EGL and OpenGL ES libraries, even for CPU
inference. If they are missing (for example in a minimal container), creating a
task fails with an error naming them; on Debian or Ubuntu install them with
`sudo apt-get install libegl1 libgles2`.

On Linux, Face Detector and Face Landmarker also accept `VisionDelegate.gpu`,
which runs Google's OpenGL ES inference and needs a GPU driver with EGL. Google's
runtime refuses software renderers such as Mesa's llvmpipe (common in virtual
machines) and machines where EGL cannot start. Creation then fails with a
`FaceDetectorException` or `FaceLandmarkerException` whose `gpuUnavailable` is
true and whose message is Google's. The package never retries on CPU. To fall
back, create a CPU task yourself:

```dart
FaceLandmarker landmarker;
try {
  landmarker = await FaceLandmarker.create(
    FaceLandmarkerOptions(modelPath: model, delegate: VisionDelegate.gpu),
  );
} on FaceLandmarkerException catch (error) {
  if (!error.gpuUnavailable) rethrow;
  landmarker = await FaceLandmarker.create(
    FaceLandmarkerOptions(modelPath: model),
  );
}
```

CI checks Linux GPU results on every change. On a hosted runner's Mesa
renderer, renamed past Google's check, both tasks match Google's own 1.0.1 GPU
output on the same runner with unchanged tolerances
([validation note](tool/validations/2026-09-23-linux-gpu/)). That verifies results, not
speed; validation on a physical GPU is pending
([`tool/test_linux_gpu.sh`](tool/test_linux_gpu.sh)). Windows has no GPU
path, because Google's Windows runtime is built with GPU disabled.

## Run locally

Use Flutter 3.44.8 / Dart 3.12.2 and Xcode. From this directory:

```sh
dart pub get
dart tool/download_model.dart
dart tool/download_face_landmarker.dart
dart tool/download_interactive_segmenter.dart # repository tests include all tasks
dart test --reporter expanded
dart run example/face_detection.dart models/blaze_face_short_range.tflite test/fixtures/face_detection/landmark-ex1.jpg
```

The first macOS build downloads the selected tasks from the public
[native runtime releases](https://github.com/hugocornellier/mediapipe_flutter_native/releases).
Face Detector is a 5.0 MB archive; Face Landmarker is 5.5 MB. Both are enabled
by default. Select only the task you use in the consuming app's `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    mediapipe_flutter_vision:
      tasks: [face_landmarker] # or [face_detector], or both
```

Task selection happens at build time, not dynamically when a Dart class is used.
An excluded task's API cannot run in that build. The Flutter example selects both
tasks for its camera and image screens. Models are separate: about 224 KB for BlazeFace and 3.8 MB for
the complete Face Landmarker bundle; each application chooses how to supply them.
When removing a task from an existing Flutter app, run `flutter clean` once to
remove native frameworks left over from earlier incremental builds.

The hook verifies the archive and library against pinned SHA-256 digests, checks
the upstream revisions and architecture, and caches the extracted runtime under
Dart/Flutter's shared hook output directory. Warm builds reuse the verified
download. Bazel, CMake, Ninja, Python, and GitHub credentials are not required
for consumer installation or inference. Flutter applications still need the
normal Xcode toolchain to build the app.

The public repository contains native artifacts and provenance. This Dart/Flutter
source repository is public. No package from this fork has been published to
pub.dev; depend on the repository or a local checkout for now.

The archive includes upstream licenses and notices; retain the applicable
notices when redistributing the native library. Models are downloaded separately.
Generated native libraries and models are ignored by Git.

Flutter macOS release builds default to universal binaries. For this arm64-only
milestone, add `EXCLUDED_ARCHS = x86_64` to the application's
`macos/Runner/Configs/AppInfo.xcconfig`. The package rejects Intel targets instead
of silently bundling an incompatible library.

## Dart API

For all 478 facial landmarks:

```dart
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

final landmarker = await FaceLandmarker.create(FaceLandmarkerOptions(
  modelPath: '/absolute/path/face_landmarker.task',
  delegate: VisionDelegate.gpu, // optional; CPU is the default
  outputFaceBlendshapes: true, // optional; false by default
  outputFacialTransformationMatrixes: true, // optional; false by default
));
try {
  final result = await landmarker.detectImage(
    VisionImage.fromFile('/absolute/path/portrait.jpg'),
  );
  for (final face in result.faceLandmarks) {
    print(face.length); // 478 with the official bundle, including irises
    print((face.first.x, face.first.y, face.first.z));
  }
} finally {
  await landmarker.dispose();
}
```

Both face task options accept `delegate: VisionDelegate.cpu` or `VisionDelegate.gpu`.
Each task's `delegate` is fixed at creation; await disposal and create a new task
to change it. GPU selects Google's Metal inference on macOS and OpenGL ES on
Linux x64 ([Linux and Windows](#linux-and-windows)). Initialization
errors are returned to the caller without retrying on CPU. The official graph
still runs some work on CPU, including Face Landmarker's blendshape stage.
CPU and GPU are included in the same download for each task; no extra backend
download is needed. GPU results can differ numerically, and GPU is not guaranteed
to be faster for every workload.

Landmark x/y are relative to input width/height. The z value is relative depth,
scaled like x, not a distance in meters. Values retain their native ordering and
are not clamped. `FaceLandmarkConnections` provides Google's tessellation,
contours, and iris edges for drawing. Transformation matrix `values` retain the
C API's column-major layout; `at(row, column)` provides indexed access.

For boxes and six keypoints only:

```dart
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

final detector = await FaceDetector.create(
  FaceDetectorOptions(modelPath: '/absolute/path/blaze_face_short_range.tflite'),
);
try {
  final result = await detector.detectImage(
    VisionImage.fromFile('/absolute/path/portrait.jpg'),
  );
  for (final face in result.detections) {
    print(face.categories.first.score);
    print(face.boundingBox.width);
    print(face.keypoints);
  }
} finally {
  await detector.dispose();
}
```

For Flutter assets, load the model with `rootBundle.load` and pass
`FaceDetectorOptions(modelBytes: data.buffer.asUint8List(
data.offsetInBytes, data.lengthInBytes))`. A Flutter asset key is not a filesystem
path. `FaceLandmarkerOptions` accepts model bytes the same way.
Apps choose whether to bundle or download their model; runtime build hooks
do not download models.

For decoded pixels and camera frames, use
`VisionImage.fromPixels(pixels: bytes, width: width, height: height,
format: VisionPixelFormat.rgb)` (or `rgba` / `bgra`). Supply `bytesPerRow` for
padded camera buffers; omit it for tightly packed pixels. The worker removes
row padding and converts BGRA channel order before passing RGB/RGBA to MediaPipe.
For Metal, RGB pixels gain an opaque alpha channel because Apple's GPU upload
requires RGBA. This preserves the original RGB values; the official task handles
resizing, normalization and all model preprocessing.
Inputs are copied and made read-only. YUV input requires conversion by the caller.
File decoding, including EXIF orientation, uses MediaPipe's image loader.

`rotationDegrees` must be a clockwise multiple of 90. Returned boxes are in pixels
of the decoded input image, and keypoints are normalized to that image. Values
are not clamped or reordered. Results remain valid after subsequent inference
and disposal. Missing keypoint confidence is represented by null.

Requests are serialized. `dispose()` finishes queued work and closes the task;
it is idempotent and rejects new requests immediately. Always await it.
Native failures become `FaceDetectorException` with a status code and message.
Face Landmarker reports `FaceLandmarkerException` with the same error fields.

For video or live camera frames, create the detector with
`runningMode: VisionRunningMode.video` and call:

```dart
final result = await detector.detectForVideo(
  frame,
  timestampMilliseconds: timestamp,
);
```

This calls the official `MpFaceDetectorDetectForVideo` API on the worker isolate.
Timestamps are nonnegative milliseconds and must strictly increase in submission
order. Each submitted timestamp is reserved even when that frame fails. Results
include `timestampMilliseconds`; still-image results leave it null. Each detector
has a fixed mode and rejects methods for the other mode.

For live capture, await each inference and skip incoming frames while busy. This
bounds latency without changing MediaPipe's task graph. Native LIVE_STREAM
callbacks are not yet exposed by this wrapper.

Face Landmarker supports the same `runningMode` and `detectForVideo` interface.
Its official graph performs tracking and, with the default `numFaces: 1`, video
smoothing. Set `numFaces` when creating the task to enable multiple faces;
MediaPipe disables that smoothing when the maximum exceeds one. The camera
demo uses the default single-face behavior without additional Dart smoothing.

## Validation and provenance

The integration suite consumes checked-in reference outputs generated through
Google's official `mediapipe==1.0.0` Python API, with separate CPU and GPU goldens.
It checks boxes, scores, keypoints,
image dimensions, file hashes, raw inputs, rotation, multiple detections, empty
results, initialization failures, and resource lifecycle.
Landmarker references cover every 3D coordinate, blendshape score, and transform
in ten still images and two tracking sequences, plus both libraries running
concurrently. Numeric tolerances and measured differences from Google's wheel
are recorded in [the Face Landmarker reference notes](test/fixtures/face_landmarker/README.md).

Hosted CI generates GPU reference outputs with the pinned official Python wheel
on the same runner, then runs the Dart suites against those outputs with the
existing tolerances, on macOS (Metal) and on Linux (Mesa, renamed past Google's
software-renderer check). CPU references remain checked in. Missing reference
files or unverified runtime or GPU provenance fail validation. See
[the GPU comparison guide](tool/GPU_VALIDATION.md).

[Benchmark instructions and measurements](tool/BENCHMARKING.md) compare CPU and
Metal through the public VIDEO API using a 1080p portrait replay in a native AOT
app. They include input conversion and result copying, without accessing a camera.

`python3 tool/test_flutter_macos.py` generates an isolated Flutter host, runs a
macOS integration test, then builds and launches a release app that verifies
inference with bundled assets. The generated host is outside the package's
source tree, under the repository's ignored `build/` directory.

`python3 tool/test_prebuilt_macos.py` creates a fresh package copy with no native
source, local library, or build cache. It tests the actual public download and
debug/release inference while blocking Bazel, Bazelisk, CMake, and Ninja. This
also runs in its own CI job. Download tests cover offline cache reuse, corruption
recovery, concurrent installation, checksum failures, and invalid archives.

## Native builds and releases

Maintainers can still build the official runtime with Python 3, Xcode, and
`brew install bazelisk cmake ninja`:

```sh
python3 tool/build_native.py
```

One invocation builds `//mediapipe/tasks/c:libmediapipe`, Google's own wheel
target, which exports every task the open-source C API offers: 11 vision tasks,
the 3 classic text tasks and the audio classifier. Linking each task into its own
dylib instead would repeat the shared graph runtime, about 12 MB, in every one.
The task list is read from that target's `BUILD` dependencies rather than pinned
here, so an upstream addition or removal shows up as a changed manifest instead
of drifting silently. MagicTouch, the modern stateful interactive segmenter, is
not open source and is served by core's official 1.0.1 runtime instead.

The first native build downloads pinned MediaPipe/OpenCV sources and build
dependencies; allow several minutes and several GB of build space. Later builds
reuse the Bazel/CMake caches. The hook prefers a verified package-local
`build/native/tasks/libmediapipe.dylib` when present, preserving source-build
tests.
To force the public runtime in a maintainer checkout, add this to the root app's
`pubspec.yaml`:

```yaml
hooks:
  user_defines:
    mediapipe_flutter_vision:
      prebuilt: true
```

`python3 tool/prepare_native_release.py` repackages a tested native build into
`build/releases/face-detector-v1.0.0-2/`, with deterministic archive metadata,
checksums, a public build manifest, a repository README, and release notes.
It does not upload anything. See [tool/RELEASING.md](tool/RELEASING.md) for the
release process; use `--task face_landmarker` to prepare the Face Landmarker runtime.
Every rebuild must get a new tag and reviewed digests in
`sdk_downloads.dart`; never replace the bytes behind an existing download URL.

The wide group fixture contains four people but the official short-range model
returns zero detections at the default threshold. The test preserves that
behavior. The derived close-up pair exercises two detections. Fixture provenance
and oracle settings are in [test/fixtures/face_detection](test/fixtures/face_detection/).

Regenerate Face Detector bindings with `dart tool/generate_bindings.dart`, and Face Landmarker
bindings with `dart tool/generate_bindings.dart ffigen_face_landmarker.yaml`. Original upstream
headers are checked in unchanged. The generator removes only C-linkage wrappers
in temporary copies because ffigen 21 does not traverse C++ linkage blocks.
The native smoke test checks struct/enum sizes against those original headers.

To regenerate references, create a separate Python 3.12 environment, install
`mediapipe==1.0.0`, and run `tool/generate_face_detector_reference.py`. The
script verifies the model, native wheel library, and fixture digests before
writing goldens. Ordinary tests do not require Python MediaPipe.
`tool/generate_face_landmarker_reference.py` generates the Face Landmarker references and
official drawing connections using the same pinned environment.
Pass `--delegate gpu` to either generator to regenerate the separate Metal
references. Source builds smoke-test both delegates and require a Metal creation
log before publishing a runtime marked GPU-capable. Stale CPU-only local builds
are rejected by the build hook; rebuild them or set `prebuilt: true`.

See [third_party/README.md](third_party/README.md) for exact native pins and build
details. Native LIVE_STREAM callbacks, Intel macOS,
mobile devices, and web are outside this initial implementation.
A camera plugin is not required for still-image inference.

## Live camera example

The [Flutter example](example/) uses `camera_desktop` for macOS capture and the
official VIDEO-mode Face Landmarker on a worker isolate. It shows an uncropped
preview with all 478 facial landmarks, highlighted irises, optional points, and timing. Camera access is
limited to the example; the task package remains a pure Dart/FFI dependency.
The CPU/GPU selector recreates the task and camera session when changed.

Run `make example_vision` from the repository root, or follow the
[example instructions](example/README.md). CI tests the frame pipeline using
portrait fixtures and builds the release app. A separate opt-in integration test
verifies real camera capture and stop/restart on a Mac with a camera attached.
