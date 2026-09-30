# mediapipe_flutter_vision

MediaPipe vision tasks for Dart and Flutter. Use one Dart API to detect faces
and objects, track face/hand/pose landmarks, recognize gestures, classify or
embed images, and segment images. The package uses Google's official
MediaPipe task runtimes on supported platforms.

**[Try the live gallery](https://hugocornellier.github.io/mediapipe_flutter/)** ·
**[See every task and platform](https://github.com/hugocornellier/mediapipe_flutter/blob/main/packages/mediapipe-task-vision/tool/VISION_TASKS_STATUS.md)** ·
**[Browse the Flutter example](https://github.com/hugocornellier/mediapipe_flutter/tree/main/packages/mediapipe-task-vision/example)**

> **Not published yet:** This package currently has
> `publish_to: none`. The checkout instructions below work now. Once the
> packages are published to pub.dev, apps can replace the path dependencies
> with published versions; there is no published version to install today.

## Tasks

| Kind | Dart classes |
| --- | --- |
| Detection | `FaceDetector`, `ObjectDetector` |
| Landmarks and gestures | `FaceLandmarker`, `HandLandmarker`, `PoseLandmarker`, `HolisticLandmarker`, `GestureRecognizer` |
| Classification and embedding | `ImageClassifier`, `ImageEmbedder` |
| Segmentation | `ImageSegmenter`, `InteractiveSegmenter`, `InteractiveSegmenterLegacy` |

`InteractiveSegmenter` is Google's stateful stroke-based MagicTouch task;
`InteractiveSegmenterLegacy` is the separate point-based task. Their models,
APIs and platform support differ. See the
[Interactive Segmenter guide](https://github.com/hugocornellier/mediapipe_flutter/blob/main/packages/mediapipe-task-vision/tool/INTERACTIVE_SEGMENTER.md).

## Installation

Use **Flutter 3.47.5 stable** to match CI. The package requires Dart 3.12 or
newer and the usual toolchain for your target platform. Clone the repository
beside your app:

```sh
git clone https://github.com/hugocornellier/mediapipe_flutter.git
```

Add the vision package to your app's `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  mediapipe_flutter_vision:
    path: ../mediapipe_flutter/packages/mediapipe-task-vision
```

The package registers its Android and web backends automatically. The official
iOS SDK is the default on iOS devices and arm64 simulators. Browser builds load
the pinned JavaScript/WASM runtime from jsDelivr. For offline use or a strict
Content Security Policy, see [Self-hosting the web runtime](#self-hosting-the-web-runtime).

### Self-hosting the web runtime

One setting in `mediapipe_flutter_core` covers every task family. From the app
root, `dart run mediapipe_flutter_core:web_runtime web/mediapipe` writes the
verified runtimes; then set `MediaPipeWebRuntime.baseUrl = 'mediapipe/';`
(from `package:mediapipe_flutter_vision/web_runtime.dart`) before creating a
task. See [core's README](../mediapipe-core/README.md#web-runtime).

### Choose native tasks at build time

The default native selection contains Face Detector and Face Landmarker. To
bundle only the tasks you use, add a task list to your app's `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    mediapipe_flutter_vision:
      tasks: [face_landmarker]
```

Task selection is a **build-time** choice: creating an omitted task will not
make its native runtime appear later. On macOS Apple Silicon, tasks beyond the
default face pair run on Google's engine, which `mediapipe_flutter_core`
bundles once for every family when the app sets
`hooks.user_defines.mediapipe_flutter_core.tasks_runtime: true` (see
[core's README](../mediapipe-core/README.md)). Other platforms need nothing
more than the task list. The
[support matrix](https://github.com/hugocornellier/mediapipe_flutter/blob/main/packages/mediapipe-task-vision/tool/VISION_TASKS_STATUS.md)
shows which task selections and delegates each platform serves.

## Quick start: detect face landmarks

Download Google's
[Face Landmarker task bundle](https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task)
to `assets/models/face_landmarker.task`, then declare it as a Flutter asset:

```yaml
flutter:
  assets:
    - assets/models/face_landmarker.task
```

Load the model bytes and pass a decoded RGBA image to the task:

```dart
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

Future<void> detectFaces(Uint8List rgba, int width, int height) async {
  final asset = await rootBundle.load('assets/models/face_landmarker.task');
  final task = await FaceLandmarker.create(
    FaceLandmarkerOptions(
      modelBytes: asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      ),
      numFaces: 1,
    ),
  );

  try {
    final result = await task.detectImage(
      VisionImage.fromPixels(
        pixels: rgba,
        width: width,
        height: height,
        format: VisionPixelFormat.rgba,
      ),
    );
    for (final face in result.faceLandmarks) {
      print('${face.length} landmarks'); // 478 with the official bundle
      print('First landmark: ${face.first.x}, ${face.first.y}');
    }
  } finally {
    await task.dispose();
  }
}
```

`rgba` must contain exactly `width * height * 4` bytes. The task also accepts
RGB or BGRA pixels, with `bytesPerRow` for padded camera frames. Convert YUV
camera buffers before creating a `VisionImage`. On native platforms,
`VisionImage.fromFile('/absolute/path/photo.jpg')` lets MediaPipe decode a
file. On web, `fromFile` takes a browser-accessible URL. A Flutter asset key
is **not** a native file path or browser URL: use `rootBundle.load` for model
assets, as above.

Models are not downloaded by the native runtime hook. You choose which
official model file to bundle or download in your app; the repository's
[model manifest](https://github.com/hugocornellier/mediapipe_flutter/blob/main/packages/mediapipe-task-vision/lib/models.dart)
lists the versioned models and SHA-256 values used by the gallery.

### Still images in other vision tasks

Create each task with `VisionRunningMode.image` (the default), then call its
image method. For camera or video frames, create it with
`VisionRunningMode.video` and call the corresponding video method with a
strictly increasing timestamp. The gallery exposes a **Camera / Still image**
selector for all ten tasks below on supported platforms.

| Task | Still image method | Video frame method |
| --- | --- | --- |
| Face Detector | `detectImage` | `detectForVideo` |
| Face Landmarker | `detectImage` | `detectForVideo` |
| Hand Landmarker | `detectImage` | `detectForVideo` |
| Gesture Recognizer | `recognizeImage` | `recognizeForVideo` |
| Holistic Landmarker | `detectImage` | `detectForVideo` |
| Pose Landmarker | `detectImage` | `detectForVideo` |
| Object Detector | `detectImage` | `detectForVideo` |
| Image Classifier | `classifyImage` | `classifyForVideo` |
| Image Embedder | `embedImage` | `embedForVideo` |
| Image Segmenter | `segmentImage` | `segmentForVideo` |

The stroke-based `InteractiveSegmenter` works on an image with editing strokes;
the point-based `InteractiveSegmenterLegacy` takes an image and a prompt. Neither
has a camera mode. Choose an image in the gallery's still image mode for the
ten camera-capable tasks; the Interactive Segmenter page starts with its bundled
sample image.

## Video and live cameras

Create the task in video mode, then submit frames with **strictly increasing
millisecond timestamps**:

```dart
final task = await FaceLandmarker.create(
  FaceLandmarkerOptions(
    modelBytes: modelBytes,
    runningMode: VisionRunningMode.video,
  ),
);
try {
  final result = await task.detectForVideo(
    VisionImage.fromPixels(
      pixels: frameRgba,
      width: frameWidth,
      height: frameHeight,
      format: VisionPixelFormat.rgba,
    ),
    timestampMilliseconds: elapsedMilliseconds,
  );
  print(result.faceLandmarks.length);
} finally {
  await task.dispose();
}
```

Here `modelBytes`, `frameRgba`, `frameWidth`, `frameHeight` and
`elapsedMilliseconds` come from your model loader and camera pipeline.
Keep a task alive across frames; do not recreate it for each image. Await
inference and skip incoming frames while busy to bound camera delay. The
package does not open a camera or draw an overlay for your app. The
[gallery](https://github.com/hugocornellier/mediapipe_flutter/tree/main/gallery)
shows camera capture, rotation, mirroring, delegate switching and overlays.

## CPU and GPU

CPU is the default. For a task with a supported GPU path, request it when
creating the task:

```dart
final task = await FaceLandmarker.create(
  FaceLandmarkerOptions(
    modelBytes: modelBytes,
    delegate: VisionDelegate.gpu,
  ),
);
```

The delegate is fixed for a task's lifetime. Await `dispose()` and create a
new task to switch delegates. A GPU initialization error is reported to your
app; it does not silently retry on CPU. GPU availability and numerical output
depend on the platform, task and model. Use
`queryFaceLandmarkerCapabilities()` or the
[support matrix](https://github.com/hugocornellier/mediapipe_flutter/blob/main/packages/mediapipe-task-vision/tool/VISION_TASKS_STATUS.md)
before offering a GPU toggle.

| Platform | CPU | GPU path |
| --- | --- | --- |
| Web | WASM | WebGL 2 in a worker, when supported |
| iOS | Official SDK | Metal for supported tasks |
| Android | Official SDK | Supported Android GPUs; arm64 devices |
| macOS Apple Silicon | Official native runtime | Metal for supported tasks |
| Linux x64 | Official wheel runtime | OpenGL ES for supported tasks; EGL and a GPU driver required |
| Windows x64 | Official wheel runtime | Not available |

The point-based legacy Interactive Segmenter is unavailable on Android; the
stroke-based Interactive Segmenter is unavailable on Windows. Some other GPU
paths have upstream limits. Read the
[per-task matrix](https://github.com/hugocornellier/mediapipe_flutter/blob/main/packages/mediapipe-task-vision/tool/VISION_TASKS_STATUS.md)
before depending on a particular combination.

## Runtimes, examples and troubleshooting

Native build hooks download pinned libraries and verify their digests. You do
not need to build MediaPipe or copy native libraries into a normal consuming
app. The first build needs network access for its selected runtime. Browser
tasks load the pinned JavaScript/WASM distribution from jsDelivr by default.
Models remain separate on every platform.

- [Live gallery](https://hugocornellier.github.io/mediapipe_flutter/) — try
  vision, audio and text tasks in a browser.
- [Gallery setup](https://github.com/hugocornellier/mediapipe_flutter/blob/main/gallery/README.md) — run the full Flutter application on a target device.
- [Face camera example](https://github.com/hugocornellier/mediapipe_flutter/blob/main/packages/mediapipe-task-vision/example/README.md) — smaller native app with CPU/GPU switching.
- [Platform status and known upstream limits](https://github.com/hugocornellier/mediapipe_flutter/blob/main/packages/mediapipe-task-vision/tool/VISION_TASKS_STATUS.md) — exact task availability.

If a Linux container cannot load EGL or OpenGL ES even for CPU inference,
install `libegl1` and `libgles2`. Windows builds use CPU; Google's Windows
runtime may wait for a usage-log upload during `dispose()` (see
[UP-025](https://github.com/hugocornellier/mediapipe_flutter/blob/main/upstream-issues.md#up-025-windows-task-closes-wait-for-googles-usage-logging-upload)).
If you remove a previously bundled native task from an existing Flutter app,
run `flutter clean` once to clear old bundled frameworks.

This is an independent fork of
[google/flutter-mediapipe](https://github.com/google/flutter-mediapipe), not
an official Google package. Source is Apache-2.0 licensed; the repository
retains upstream notices and runtime provenance.
