# MediaPipe Tasks for Flutter

<p align="center">
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.47.5-02569B?logo=flutter" alt="Tested with Flutter 3.47.5"></a>
  <a href="https://github.com/hugocornellier/mediapipe_flutter/actions/workflows/web.yaml"><img src="https://github.com/hugocornellier/mediapipe_flutter/actions/workflows/web.yaml/badge.svg" alt="Web CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache-2.0 license"></a>
</p>

Google's MediaPipe Tasks for Dart and Flutter on Android, iOS, macOS, Linux,
Windows and the web: detect faces and objects, track face, hand and pose
landmarks, recognize gestures, classify and embed images, text and audio,
segment images, and more. Every task runs Google's official MediaPipe
runtime for its platform, and Google's pinned models download on first use.

**[Try the live gallery](https://hugocornellier.github.io/mediapipe_flutter/)**

> **Not on pub.dev yet.** The packages set `publish_to: none` until they are
> published; for now, depend on them by path from a checkout (below).

## Which package do I need?

| Package | Use it for | Guide |
| --- | --- | --- |
| `mediapipe_vision` | Face and object detection; face, hand, pose and holistic landmarks; gestures; image classification, embeddings and segmentation | [Vision](packages/mediapipe-task-vision/README.md) |
| `mediapipe_text` | Text classification and embeddings, language detection, and on macOS EmbeddingGemma, proofreading and summarization | [Text](packages/mediapipe-task-text/README.md) |
| `mediapipe_audio` | Audio classification | [Audio](packages/mediapipe-task-audio/README.md) |

Add only the families you use. Each one depends on `mediapipe_core`, which
bundles Google's MediaPipe engine once per app however many families use it,
and holds the shared model store and browser runtime settings
([core guide](packages/mediapipe-core/README.md)). `mediapipe_genai` (LLM
inference) is a separate, experimental package.

## Quick start

Use Flutter 3.47.5 stable, the version CI tests (Dart 3.12 or newer). Clone
the repository beside your app and add a family by path:

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
```

Then create a task with one of Google's pinned models. It is downloaded,
verified against its SHA-256 and cached the first time:

```dart
import 'dart:typed_data';

import 'package:mediapipe_vision/mediapipe_vision.dart';

Future<int> countFaces(Uint8List rgba, int width, int height) async {
  final landmarker = await FaceLandmarker.create(
    FaceLandmarkerOptions(model: VisionModels.faceLandmarker),
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

A few platforms need a setting before the first download: Android the
`INTERNET` permission, a sandboxed macOS app the network client entitlement,
and macOS apps using text, audio or most vision tasks
`tasks_runtime: true`. See [platform setup](doc/platform_setup.md). Your own
models work too: pass `modelPath` or `modelBytes` instead of `model`.

## Where it runs

| Family | Android | iOS | macOS arm64 | Linux x64 | Windows x64 | Web |
| --- | --- | --- | --- | --- | --- | --- |
| Vision | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Text (classify, embed, detect language) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Text (EmbeddingGemma, proofread, summarize) | | | ✓ | | | |
| Audio | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

CPU works everywhere a family is listed; GPU (Metal, OpenGL ES, WebGL or
Android GPU) depends on the task. Every cell is tested in CI on hosted
runners, the Android emulator, the iOS Simulator and Chromium, Firefox and
WebKit. The [vision status table](packages/mediapipe-task-vision/tool/VISION_TASKS_STATUS.md)
lists each task, delegate, known upstream limit and physical-device result.
Ask at run time with the `queryXxxCapabilities()` functions: they report the
supported delegates and why any other is unavailable.

## More

- Samples for every task:
  [vision](packages/mediapipe-task-vision/README.md#samples-for-every-task),
  [text](packages/mediapipe-task-text/README.md#quick-start) and
  [audio](packages/mediapipe-task-audio/README.md#use).
- [Platform setup](doc/platform_setup.md): permissions, entitlements, minimum
  OS versions, offline builds and browser hosting.
- [Privacy and licenses](doc/privacy_and_licenses.md): what is downloaded, from
  where, and under which license.
- [Migration](MIGRATION.md) from `mediapipe_flutter_*` and from Google's
  `mediapipe_text` 0.0.1.
- [Gallery](gallery/README.md): the full demo app, also
  [live on GitHub Pages](https://hugocornellier.github.io/mediapipe_flutter/).
- [Contributing](CONTRIBUTING.md), including how to add a task.

## Origin and license

An independent continuation of
[google/flutter-mediapipe](https://github.com/google/flutter-mediapipe),
maintained by [Hugo Cornellier](https://github.com/hugocornellier); it is not
an official Google package. Source is licensed under [Apache-2.0](LICENSE),
with upstream notices retained; [UPSTREAM.md](UPSTREAM.md) records the
provenance.
