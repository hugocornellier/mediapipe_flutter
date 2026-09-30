# MediaPipe Tasks for Flutter

<p align="center">
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.47.5-02569B?logo=flutter" alt="Tested with Flutter 3.47.5"></a>
  <a href="https://github.com/hugocornellier/mediapipe_flutter/actions/workflows/web.yaml"><img src="https://github.com/hugocornellier/mediapipe_flutter/actions/workflows/web.yaml/badge.svg" alt="Web CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache-2.0 license"></a>
</p>

Run Google's MediaPipe Tasks from Dart and Flutter: detect faces and objects,
track landmarks, classify images and audio, embed text, and more. The vision
package exposes one Dart API for still images and video frames, with official
MediaPipe runtimes selected for each supported platform.

**[Try the live gallery](https://hugocornellier.github.io/mediapipe_flutter/)** ·
**[Vision package guide](packages/mediapipe-task-vision/README.md)** ·
**[Task and platform support](packages/mediapipe-task-vision/tool/VISION_TASKS_STATUS.md)**

> **Publication status:** These packages are not on pub.dev yet; their
> manifests currently set `publish_to: none`. This guide is written for app
> developers, and the local checkout instructions below work today. Do not use
> a `flutter pub add mediapipe_flutter_*` command until the packages are
> published.

## Packages

| Package | Use it for | Guide |
| --- | --- | --- |
| `mediapipe_vision` | Face, hand, pose, gesture and holistic landmarks; detection, classification, embedding and segmentation | [Vision](packages/mediapipe-task-vision/README.md) |
| `mediapipe_text` | Language detection, text classification and embedding, plus supported modern text tasks | [Text](packages/mediapipe-task-text/README.md) |
| `mediapipe_audio` | Audio classification | [Audio](packages/mediapipe-task-audio/README.md) |

`mediapipe_core` supplies shared types and native runtimes where tasks
need them. Web and Android vision use companion adapter packages; the
[Vision installation guide](packages/mediapipe-task-vision/README.md#installation)
shows when to add them. The GenAI package remains experimental and is not part
of this getting-started path.

## Quick start: Face Landmarker

Use Flutter **3.47.5 stable** for the version exercised in CI. The packages
require Dart 3.12 or newer. For now, clone the repository beside your app and
add the vision package by path:

```sh
git clone https://github.com/hugocornellier/mediapipe_flutter.git
```

```yaml
# Your app's pubspec.yaml
dependencies:
  flutter:
    sdk: flutter
  mediapipe_vision:
    path: ../mediapipe_flutter/packages/mediapipe-task-vision

flutter:
  assets:
    - assets/models/face_landmarker.task
```

Download the [official Face Landmarker model](https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task)
to `assets/models/face_landmarker.task`. Models are supplied by your app;
native runtime downloads do not include them.

```dart
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';

Future<int> countFaces(Uint8List rgba, int width, int height) async {
  final model = await rootBundle.load('assets/models/face_landmarker.task');
  final landmarker = await FaceLandmarker.create(
    FaceLandmarkerOptions(
      modelBytes: model.buffer.asUint8List(
        model.offsetInBytes,
        model.lengthInBytes,
      ),
    ),
  );
  try {
    final result = await landmarker.detectImage(
      VisionImage.fromPixels(
        pixels: rgba,
        width: width,
        height: height,
        format: VisionPixelFormat.rgba,
      ),
    );
    return result.faceLandmarks.length;
  } finally {
    await landmarker.dispose();
  }
}
```

Pass decoded RGBA bytes to this function. For camera frames, convert the
camera's pixel format first and use `RunningMode.video` with increasing
timestamps. The [Vision guide](packages/mediapipe-task-vision/README.md#video-and-live-cameras)
shows the video call and platform setup.

The gallery lets you switch between **Camera** and **Still image** on Face
Detector, Face Landmarker, Hand Landmarker, Gesture Recognizer, Holistic
Landmarker, Pose Landmarker, Object Detector, Image Classifier, Image Embedder
and Image Segmenter. In still image mode, choose a JPG, PNG or WebP file and
the same settings and delegate apply to that image. Interactive Segmenter is
an image editor and has no camera mode.

## What runs where?

| Platform | Vision runtime | Delegates |
| --- | --- | --- |
| Web | Official MediaPipe Tasks Vision JavaScript/WASM adapter | CPU/WASM, WebGL 2 |
| iOS | Official MediaPipe iOS SDK | CPU, Metal where supported |
| Android | Official MediaPipe Android SDK adapter | CPU, GPU on supported devices |
| macOS Apple Silicon | Official MediaPipe native runtime | CPU, Metal where supported |
| Linux x64 | Official MediaPipe wheel runtime | CPU, OpenGL ES for supported tasks |
| Windows x64 | Official MediaPipe wheel runtime | CPU |

Availability varies by task. The [support matrix](packages/mediapipe-task-vision/tool/VISION_TASKS_STATUS.md)
names every task, delegate and known upstream limit. CPU is the default;
requesting GPU never silently switches to CPU if initialization fails.

## Models, builds and examples

- **Models are separate from runtimes.** Bundle the model as a Flutter asset or
  download it in your app. Flutter asset keys belong in `modelBytes` after
  `rootBundle.load`; `modelPath` is a native file path or a browser URL.
- **Native runtimes are selected at build time.** The build hooks download and
  verify the native libraries for supported targets. Select the tasks your app
  uses under `hooks.user_defines.mediapipe_vision.tasks` to avoid
  bundling unused runtimes.
- **Web and Android require adapters.** Add their companion packages when
  targeting those platforms. A checkout also needs the verified web runtime
  prepared before a web build. See [Installation](packages/mediapipe-task-vision/README.md#installation).
- **Live capture is app code.** The package processes images and video frames;
  use a Flutter camera plugin to capture frames. The
  [gallery](gallery/README.md) demonstrates camera lifecycle, overlays and
  delegate switching.

For a complete Flutter app, clone this repository and follow the
[gallery setup](gallery/README.md). The [Face Landmarker example](packages/mediapipe-task-vision/example/README.md)
is a smaller native camera app. The gallery is also
[deployed on GitHub Pages](https://hugocornellier.github.io/mediapipe_flutter/).

## Origin and license

This is an independent development fork of
[google/flutter-mediapipe](https://github.com/google/flutter-mediapipe),
maintained by [Hugo Cornellier](https://github.com/hugocornellier); it is not
an official Google package. MediaPipe runtime and model provenance is recorded
in [UPSTREAM.md](UPSTREAM.md) and the package guides. Source is licensed under
[Apache-2.0](LICENSE), with upstream notices retained.
