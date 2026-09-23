# MediaPipe Gallery

One app for the interactive MediaPipe demos this repository supports on the
platform you run it on. A task appears as a tile only when its runtime is
bundled, its support is validated here, and it has a screen to show.

## Running it

**Web:** [try the live Face Landmarker demo](https://hugocornellier.github.io/mediapipe_flutter/),
or run `python3.12 -B gallery/tool/prepare.py --target web` from the root, then
`cd gallery && flutter run -d chrome --release`. Web exposes FaceLandmarker CPU
and GPU, with Google's pinned official JS/WASM runtime on a worker. Select GPU
in Live Face Landmarker to use WebGL 2. Allow camera
access on HTTPS or localhost. See [web tests and deployment](tool/WEB_FACE.md).

The pubspec and assets are generated, because the task list is per target and
the build hook rejects a task it has no runtime for. Download the models once,
then prepare and run:

```sh
cd packages/mediapipe-task-vision
dart tool/download_model.dart
dart tool/download_face_landmarker.dart
cd ../..
python3 -B gallery/tool/prepare.py
cd gallery && flutter run -d macos --release
```

`prepare.py --target <platform>` prepares a different target, for example
`ios-simulator/arm64` or `android/arm64`. It also pins the macOS build to arm64,
excludes the x86_64 simulator slice, and adds the camera entitlement and usage
description, none of which `flutter create` provides. For macOS it also
verifies Google's pinned 1.0.0 wheel, prepares its official runtime, and opts
Live Face Landmarker, Live Hand Landmarker and Live Pose Landmarker into it. The ordinary package runtime
rows remain unchanged.

For Android, `python3 gallery/tool/prepare.py --target android/arm64` selects
Google's released vision SDK and its Flutter plugin. Live Face Landmarker and
Live Hand Landmarker support CPU and GPU, with Android YUV camera conversion.
Hand has run on an emulator's CPU only so far; see
[its status](../packages/mediapipe-task-vision/tool/HAND_LANDMARKER_STATUS.md). A physical Pixel 7
Test Lab run validates both delegates and front/back camera capture; see
[the Android Test Lab guide](tool/ANDROID_FACE_TESTLAB.md) to reproduce it
without owning an Android device.

For Windows x64 and Linux x64, prepare with `--target windows/x64` or
`--target linux/x64`, then run `flutter run -d windows --release` or
`flutter run -d linux --release`. Linux offers GPU for the live Face and Hand
Landmarker demos; Windows and the Pose demo use CPU only.
The hook extracts Google's checksum-pinned native library from its official
wheel; the installed app does not need Python. `camera_desktop` provides native
Media Foundation capture on Windows and GStreamer/V4L2 capture on Linux.
Linux builds need `libgstreamer1.0-dev`, `libgstreamer-plugins-base1.0-dev` and
`gstreamer1.0-plugins-good` in addition to Flutter's desktop dependencies.

## What decides the tiles

Three gates, in order:

1. **Bundled**: `tool/prepare.py` reads `sdk_downloads.dart` and selects the
   tasks whose runtime this target can actually obtain. Unpublished runtimes
   count only when a maintainer build is present in the package.
2. **Validated**: `lib/catalog.dart` asks the package's own capability query.
   Nothing restates support by hand, so a task validated on a new platform
   appears here with no code change.
3. **Demonstrable**: a screen of its own, which is what `GalleryDemo` names.
   Entries without one are known to the gallery but never become tiles.

Anything bundled but not validated, and anything validated without a screen, is
listed in the about sheet with the package's own reason rather than hidden.

The visible tiles depend on the target and follow the package's
[status table](../packages/mediapipe-task-vision/tool/VISION_TASKS_STATUS.md):
each validated task with a screen appears, including the MagicTouch stroke
editor wherever its runtime runs.

## Live camera

`lib/live/` shares camera capture, serial VIDEO-mode inference, frame skipping,
timings, camera switching, stop/start, cleanup and overlay geometry across live
tasks. It handles desktop RGBA, Apple BGRA and Android YUV camera buffers.
Windows exposes CPU only. Face and Hand Landmarker also expose GPU on Linux,
Apple platforms, Android and web.
Web uses browser-native capture and transferable bitmaps while sharing these
controls and the same overlay painter. Web GPU requires worker WebGL 2 support.

## Tests

```sh
cd gallery
flutter test -d macos integration_test/assets_test.dart
flutter test -d macos integration_test/runtime_test.dart
```

Run one file per invocation: `flutter test -d macos integration_test/` cannot
start a second app instance on the device and fails to load the later file.

These check the bundle the app was actually built with: that every visible tile
can load its model and sample, and that the live demo's model resolves. Both
derive their asset names from the catalog, so they cannot drift from what the
screens ask for.

The Desktop tasks workflow also builds the actual Windows/Linux gallery,
checks native camera plugin registration and enumeration, visits all live task
runtimes in one process, and drives the Face Landmarks page with supplied portrait
frames through Google's real CPU task. It checks padded RGBA/BGRA, 478-point
results, camera switching, stop/start, cleanup and a release gallery build.
Hosted runners have no physical webcam, so the real-camera workflows supply one:
Linux streams the licensed portrait into a v4l2loopback device and Windows
registers a Media Foundation virtual camera showing it (`tool/windows/vcam`).
Both run `integration_test/real_camera_test.dart`, which checks capture, a face
across stop/restart, and overlay alignment against the on-screen preview; the
status matrix links the records. A physical webcam still differs in formats and
exposure, so a manual pass remains useful. To check capture, prepare the target
then use `flutter run -d windows --release -t tool/live_face_camera_smoke.dart`
(or `-d linux`). It processes twenty CPU camera frames twice and records JSON in
the system temporary directory; put a face in view and check the face count.
Run the normal gallery's Live Face Landmarker page to check preview mirroring and
visual landmark alignment; the smoke test displays counts rather than an overlay.
