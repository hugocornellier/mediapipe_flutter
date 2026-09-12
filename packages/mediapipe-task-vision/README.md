# mediapipe_flutter_vision

Official MediaPipe Face Detector for Dart and Flutter on **macOS arm64**.
This development version implements **CPU IMAGE and VIDEO modes**. It accepts JPEG/image
files or RGB/RGBA/BGRA pixels and returns face boxes, categories, and
six keypoints. Inference runs on a worker isolate.

The task uses the unmodified MediaPipe v1.0.0 Face Detector graph and its official
BlazeFace short-range float16 model, version 1. MediaPipe performs image
preprocessing, model inference, anchor decoding, suppression, and coordinate
projection. The Dart wrapper copies results and owns native resource cleanup.

## Run locally

Use Flutter 3.44.8 / Dart 3.12.2 and Xcode. From this directory:

```sh
dart pub get
dart tool/download_model.dart
dart test --reporter expanded
dart run example/face_detection.dart models/blaze_face_short_range.tflite test/fixtures/face_detection/landmark-ex1.jpg
```

The first build downloads a 4.2 MB native archive from the public
[native runtime release](https://github.com/hugocornellier/mediapipe_flutter_native/releases/tag/face-detector-v1.0.0-1).
The hook verifies the archive and library against pinned SHA-256 digests, checks
the upstream revisions and architecture, and caches the extracted runtime under
Dart/Flutter's shared hook output directory. Warm builds reuse the verified
download. Bazel, CMake, Ninja, Python, and GitHub credentials are not required
for consumer installation or inference. Flutter applications still need the
normal Xcode toolchain to build the app.

The public repository contains native artifacts and provenance. This Dart/Flutter
source repository remains private; access to it is still required to obtain the
package. No package from this fork has been published to pub.dev.

The archive includes upstream licenses and notices; retain the applicable
notices when redistributing the native library. Models are downloaded separately.
Generated native libraries and models are ignored by Git.

Flutter macOS release builds default to universal binaries. For this arm64-only
milestone, add `EXCLUDED_ARCHS = x86_64` to the application's
`macos/Runner/Configs/AppInfo.xcconfig`. The package rejects Intel targets instead
of silently bundling an incompatible library.

## Dart API

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
path. Apps choose whether to bundle or download their model; runtime build hooks
do not download models.

For decoded pixels and camera frames, use
`VisionImage.fromPixels(pixels: bytes, width: width, height: height,
format: VisionPixelFormat.rgb)` (or `rgba` / `bgra`). Supply `bytesPerRow` for
padded camera buffers; omit it for tightly packed pixels. The worker removes
row padding and converts BGRA channel order before passing RGB/RGBA to MediaPipe.
Inputs are copied and made read-only. YUV input requires conversion by the caller.
File decoding, including EXIF orientation, uses MediaPipe's image loader.

`rotationDegrees` must be a clockwise multiple of 90. Returned boxes are in pixels
of the decoded input image, and keypoints are normalized to that image. Values
are not clamped or reordered. Results remain valid after subsequent inference
and disposal. Missing keypoint confidence is represented by null.

Requests are serialized. `dispose()` finishes queued work and closes the task;
it is idempotent and rejects new requests immediately. Always await it.
Native failures become `FaceDetectorException` with a status code and message.

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

## Validation and provenance

The integration suite consumes checked-in reference outputs generated through
Google's official `mediapipe==1.0.0` Python API. It checks boxes, scores, keypoints,
image dimensions, file hashes, raw inputs, rotation, multiple detections, empty
results, initialization failures, and resource lifecycle.

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

The first native build downloads pinned MediaPipe/OpenCV sources and build
dependencies; allow several minutes and several GB of build space. Later builds
reuse the Bazel/CMake caches. The hook prefers a verified package-local
`build/native/libface_detector.dylib` when present, preserving source-build tests.
To force the public runtime in a maintainer checkout, add this to the root app's
`pubspec.yaml`:

```yaml
hooks:
  user_defines:
    mediapipe_flutter_vision:
      prebuilt: true
```

`python3 tool/prepare_native_release.py` repackages a tested native build into
`build/releases/face-detector-v1.0.0-1/`, with deterministic archive metadata,
checksums, a public build manifest, a repository README, and release notes.
It does not upload anything. See [tool/RELEASING.md](tool/RELEASING.md) for the
release process. Every rebuild must get a new tag and reviewed digests in
`sdk_downloads.dart`; never replace the bytes behind an existing download URL.

The wide group fixture contains four people but the official short-range model
returns zero detections at the default threshold. The test preserves that
behavior. The derived close-up pair exercises two detections. Fixture provenance
and oracle settings are in [test/fixtures/face_detection](test/fixtures/face_detection/).

Regenerate bindings with `dart tool/generate_bindings.dart`. Original upstream
headers are checked in unchanged. The generator removes only C-linkage wrappers
in temporary copies because ffigen 21 does not traverse C++ linkage blocks.
The native smoke test checks struct/enum sizes against those original headers.

To regenerate references, create a separate Python 3.12 environment, install
`mediapipe==1.0.0`, and run `tool/generate_face_detector_reference.py`. The
script verifies the model, native wheel library, and fixture digests before
writing goldens. Ordinary tests do not require Python MediaPipe.

See [third_party/README.md](third_party/README.md) for exact native pins and build
details. Native LIVE_STREAM callbacks, Face Landmarker/iris, Intel macOS,
mobile devices, Linux, Windows, and web are outside this initial implementation.
A camera plugin is not required for still-image inference.
