# MediaPipe browser FaceLandmarker

Flutter web adapter for Google's unmodified **@mediapipe/tasks-vision 1.0.1**
JavaScript/WASM distribution. FaceLandmarker supports CPU and GPU IMAGE and VIDEO modes,
478 landmarks, optional 52 blendshapes and column-major facial transforms.
Other tasks are not exposed by this adapter yet. Select GPU in the live gallery
or use `delegate: VisionDelegate.gpu`. GPU uses the official WebGL 2 delegate
on an `OffscreenCanvas` owned by the inference worker. A browser without worker
WebGL 2 support reports an error; choose CPU to recover. GPU never silently
falls back to the CPU delegate.

[Try the live camera gallery](https://hugocornellier.github.io/mediapipe_flutter/).
Camera frames are processed within your browser. Use HTTPS or localhost and
allow camera access. Modern Chrome is validated for live capture; Chrome and
Firefox are validated against Google's official JavaScript results. Safari and
mobile browsers have not been validated in this implementation.

## Prepare and run the gallery

From the repository root, with Flutter 3.44.8 and Python 3.12:

```sh
python3.12 -B gallery/tool/prepare.py --target web
cd gallery
flutter run -d chrome --release
```

Preparation verifies the official NPM tarball's pinned SHA-512 and the model's
pinned SHA-256, then bundles runtime assets locally. Generated downloads are
ignored by Git. There is no runtime dependency on a public JS/WASM CDN.

## Use the public Dart API

Add both `mediapipe_flutter_vision` and `mediapipe_flutter_vision_web` to the
Flutter app's dependencies; see the generated gallery pubspec for local paths.
Flutter registers the adapter automatically. Prepare its runtime assets with
`python3.12 -B packages/mediapipe-task-vision-web/tool/prepare_runtime.py` before
building an app outside the gallery preparation flow.

Using the gallery's asset layout:

```dart
import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

final model = await rootBundle.load('assets/models/face_landmarker.task');
final task = await FaceLandmarker.create(FaceLandmarkerOptions(
  modelBytes: model.buffer.asUint8List(model.offsetInBytes, model.lengthInBytes),
  outputFaceBlendshapes: true,
  outputFacialTransformationMatrixes: true,
));
try {
  final result = await task.detectImage(
    VisionImage.fromFile('assets/assets/samples/portrait.jpg'),
  );
  print(result.faceLandmarks.first.length);
} finally {
  await task.dispose();
}
```

`modelPath` and `VisionImage.fromFile` refer to browser-accessible URLs on web;
remote URLs need normal browser CORS permission. Model bytes and RGB/RGBA/BGRA
pixels are copied before transport. Results remain valid after later frames and
disposal. VIDEO timestamps must strictly increase, including after a failed
frame. Runtime failures, including unavailable GPU initialization, use
`FaceLandmarkerException` rather than silently selecting CPU.

Each task owns a module worker, which serializes inference and shutdown. The
gallery captures with `getUserMedia`, transfers `ImageBitmap` frames, skips busy
frames, and reuses the native gallery's controls and mesh painter. It handles
camera switching, mirroring, permission denial, missing/disconnected cameras,
worker failure, stop/restart and navigation cleanup.

## Verification and deployment

See [the web test guide](../../gallery/tool/WEB_FACE.md). GitHub Actions runs
real release-mode browser inference and live capture with a file-backed webcam.
Firefox uses Xvfb and Mesa software WebGL on hosted Linux for the official CPU
task's image preprocessing; this does not validate the GPU inference delegate.
The public Pages job publishes the exact tested release artifact, then repeats
camera/lifecycle checks against the deployed HTTPS URL. `build-info.json`
records its source SHA and runtime/model provenance.

This adapter and the official MediaPipe distribution use Apache-2.0; the
repository's upstream notices and model/sample provenance are retained.
