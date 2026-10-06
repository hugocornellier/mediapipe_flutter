# MediaPipe Face Camera

Live camera facial landmarks on macOS Apple Silicon using `camera_desktop` and the
official MediaPipe v1.0.0 Face Landmarker. Requires Flutter 3.47.5 / Dart 3.13.4 and
Xcode. macOS native runtimes download automatically when local builds are absent.
The same example opens a CPU image demo on arm64 iOS simulators; follow the
[simulator guide](../tool/IOS_SIMULATOR.md) to build its local native libraries.

From this directory:

```sh
dart ../tool/download_model.dart
dart ../tool/download_face_landmarker.dart
python3 -B ../tool/prepare_face_example.py
flutter pub get
flutter run -d macos --release
```

Select a camera and press **Start camera**. macOS may ask for camera permission.
Choose **CPU** (the default) or **GPU (Metal)**. Changing the selection while live
drains the current inference and recreates the task before restarting capture.
Both delegates are included in the same runtime download. GPU initialization
errors appear in the UI; the demo does not silently switch to CPU.

To launch directly into a live GPU session:

```sh
flutter run -d macos --release --dart-define=FACE_CAMERA_DELEGATE=gpu --dart-define=FACE_CAMERA_AUTOSTART=true
```

These flags are opt-in. A normal launch starts idle with CPU selected.
If access was previously denied, enable the app in System Settings → Privacy &
Security → Camera. The example requests camera access only; audio is disabled.

The preview shows all 478 facial landmarks and their connections, with highlighted iris
rings, and measured frame rate and latency. **Connections** and **Points** toggle the
overlay. Use **Stop camera** to release capture. Frames are processed on the Mac
and are not recorded or uploaded. This uses Google's unmodified Face Landmarker
bundle, which includes a short-range face detector; small distant faces can be missed.

## Frame handling

The landmarker runs in live stream mode on its worker isolate, with one face
and MediaPipe's built-in tracking/smoothing. The demo gives each camera frame
a strictly increasing elapsed-time timestamp when it arrives and submits it;
the task runs one frame at a time, keeps the newest one waiting and drops the
others, as Google's live stream does. The worker converts
BGRA to RGBA and removes camera row padding; MediaPipe handles all model
preprocessing, inference, tracking, and coordinate projection. Blendshapes and
transformation matrices are available through the package API; this landmark-only
demo leaves those optional outputs disabled.

On macOS, `camera_desktop` mirrors the capture buffer used by both its preview
and image stream. The overlay scales the returned input coordinates directly
onto an uncropped preview, without applying another mirror. Stopping, switching
cameras, or hiding the app releases capture and drains active inference.

The example selects both face tasks for its camera and image screens. Verified
local builds take precedence; macOS downloads are used when local builds are
absent. The simulator currently requires local CPU libraries. Fixture copies
and models are prepared from the package's canonical inputs by the command above.
The package runs live stream mode on Google's VIDEO graph, with Google's frame
dropping in front of it, so a dropped frame never reaches the worker isolate.

## Tests

`flutter test` exercises the camera controller with padded portrait frames and
the real native landmarker, including CPU → GPU → CPU switching, 478-point output,
frame dropping, restart, cancellation during
initialization, and recovery after permission denial. These tests need no camera.

The existing `face_detection.dart` remains a command-line still-image example.
