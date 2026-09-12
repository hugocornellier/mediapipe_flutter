# MediaPipe Face Camera

Live camera face mesh on macOS Apple Silicon using `camera_desktop` and the
official MediaPipe v1.0.0 Face Landmarker. Requires Flutter 3.44.8 / Dart 3.12.2 and
Xcode. The native runtime downloads automatically from the pinned public release.

From this directory:

```sh
flutter pub get
dart ../tool/download_face_landmarker.dart assets/face_landmarker.task
flutter run -d macos --release
```

Select a camera and press **Start camera**. macOS may ask for camera permission.
If access was previously denied, enable the app in System Settings → Privacy &
Security → Camera. The example requests camera access only; audio is disabled.

The preview shows all 478 landmarks as a connected mesh, with highlighted iris
rings, and measured frame rate and latency. **Mesh** and **Points** toggle the
overlay. Use **Stop camera** to release capture. Frames are processed on the Mac
and are not recorded or uploaded. This uses Google's unmodified FaceMesh V2
bundle, which includes a short-range face detector; small distant faces can be missed.

## Frame handling

The landmarker runs in official VIDEO mode on its worker isolate, with one face
and MediaPipe's built-in tracking/smoothing. The demo gives
each submitted frame a strictly increasing elapsed-time timestamp and allows
one inference at a time, skipping incoming frames while busy. The worker converts
BGRA to RGBA and removes camera row padding; MediaPipe handles all model
preprocessing, inference, tracking, and coordinate projection. Blendshapes and
transformation matrices are available through the package API; this mesh-only
demo leaves those optional outputs disabled.

On macOS, `camera_desktop` mirrors the capture buffer used by both its preview
and image stream. The overlay scales the returned input coordinates directly
onto an uncropped preview, without applying another mirror. Stopping, switching
cameras, or hiding the app releases capture and drains active inference.

The demo explicitly uses the prebuilt runtime even in a maintainer checkout.
Its hook configuration selects only `face_landmarker`, so the standalone
Face Detector library is not downloaded or bundled for this app.
Native LIVE_STREAM callbacks are not exposed by the Dart wrapper yet; live
capture here uses the official synchronous VIDEO API off the UI isolate.

## Tests

`flutter test` exercises the camera controller with padded portrait frames and
the real native landmarker, including 478-point output, frame skipping, restart, cancellation during
initialization, and recovery after permission denial. These tests need no camera.

To test a real camera, including capture restart:

```sh
flutter test -d macos integration_test/live_camera_test.dart --dart-define=CAMERA_HARDWARE_TEST=true
```

For an automatic hardware check in release mode:

```sh
flutter build macos --release -t tool/release_camera_smoke.dart
build/macos/Build/Products/Release/mediapipe_face_camera.app/Contents/MacOS/mediapipe_face_camera
```

The release check processes at least 60 frames, stops capture, and exits with a
nonzero code on failure. Run `flutter run -d macos --release` afterward to rebuild
and launch the interactive demo. Hardware tests are opt-in and do not run on CI.

The existing `face_detection.dart` remains a command-line still-image example.
