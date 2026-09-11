# mediapipe_flutter_vision

Official MediaPipe Face Detector for Dart and Flutter on **macOS arm64**.
This development version implements **CPU IMAGE mode**. It accepts JPEG/image
files or tightly packed RGB/RGBA pixels and returns face boxes, categories, and
six keypoints. Inference runs on a worker isolate.

The task uses the unmodified MediaPipe v1.0.0 Face Detector graph and its official
BlazeFace short-range float16 model, version 1. MediaPipe performs image
preprocessing, model inference, anchor decoding, suppression, and coordinate
projection. The Dart wrapper copies results and owns native resource cleanup.

## Run locally

Use Flutter 3.44.8 / Dart 3.12.2, Xcode, Python 3, and
`brew install bazelisk cmake ninja`. From this directory:

```sh
dart pub get
dart tool/download_model.dart
python3 tool/build_native.py
dart test --reporter expanded
dart run example/face_detection.dart models/blaze_face_short_range.tflite test/fixtures/face_detection/landmark-ex1.jpg
```

The first native build downloads pinned MediaPipe/OpenCV sources and their build
dependencies; allow several minutes and several GB of build space. Later builds
reuse the Bazel/CMake caches. No Python package is needed for inference.

This is currently a **maintainer source-build bootstrap**, not a published
download-on-build SDK. The build hook bundles `build/native/libface_detector.dylib`
with the app and rejects unsupported targets. The native builder also prepares
`build/native/mediapipe-face-detector-1.0.0-macos-arm64.tar.gz`, including checksums,
build metadata, and notices. Publishing a reviewed artifact and pinning its URL
in the hook is the remaining step before consumers can skip native compilation.
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

For decoded pixels, use
`VisionImage.fromPixels(pixels: bytes, width: width, height: height,
format: VisionPixelFormat.rgb)` (or `rgba`). Buffers must be tightly packed;
convert BGRA/YUV and remove row padding before calling. Inputs are copied and
made read-only. File decoding, including EXIF orientation, uses MediaPipe's image
loader.

`rotationDegrees` must be a clockwise multiple of 90. Returned boxes are in pixels
of the decoded input image, and keypoints are normalized to that image. Values
are not clamped or reordered. Results remain valid after subsequent inference
and disposal. Missing keypoint confidence is represented by null.

Requests are serialized. `dispose()` finishes queued work and closes the task;
it is idempotent and rejects new requests immediately. Always await it.
Native failures become `FaceDetectorException` with a status code and message.

## Validation and provenance

The integration suite consumes checked-in reference outputs generated through
Google's official `mediapipe==1.0.0` Python API. It checks boxes, scores, keypoints,
image dimensions, file hashes, raw inputs, rotation, multiple detections, empty
results, initialization failures, and resource lifecycle.

`python3 tool/test_flutter_macos.py` generates an isolated Flutter host, runs a
macOS integration test, then builds and launches a release app that verifies
inference with bundled assets. The generated host is outside the package's
source tree, under the repository's ignored `build/` directory.

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
details. Live/video modes, camera capture, Face Landmarker/iris, Intel macOS,
mobile devices, Linux, Windows, and web are outside this initial implementation.
A camera plugin is not required for still-image inference.
