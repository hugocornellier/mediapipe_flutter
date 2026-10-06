# MediaPipe Gallery

One app for the interactive MediaPipe demos this repository supports on the
platform you run it on. A task appears as a tile only when its runtime is
bundled, its support is validated here, and it has a screen to show.

## Running it

**Web:** [try the gallery](https://hugocornellier.github.io/mediapipe_flutter/),
or run `python3.12 -B gallery/tool/prepare.py --target web` from the root, then
`cd gallery && flutter run -d chrome --release`. Supported vision tasks use
Google's pinned official JS/WASM runtime on a worker; GPU tasks use WebGL 2.
Allow camera
access on HTTPS or localhost. See [web tests and deployment](tool/WEB_FACE.md).

The pubspec and assets are generated, because the task list is per target and
the build hook rejects a task it has no runtime for. On a Mac with Apple
Silicon, a clean checkout needs only Flutter and Xcode:

```sh
dart run tool/gallery_builder/bin/prepare_gallery.dart --target macos/arm64
cd gallery
flutter run -d macos --release
```

The Dart preparer downloads and verifies every model the target needs, and
fails rather than build an incomplete app. For macOS it also sets
`mediapipe_core.tasks_runtime: true`, so vision, text and audio all run on
Google's 1.0.0 macOS engine, which core bundles once for the whole app, as it
would for any app that opts in. The checked-in macOS project already pins the
build to arm64 and declares the camera entitlement and usage description.

`python3.12 -B gallery/tool/prepare.py --target <platform>` prepares iOS,
Linux, Windows and the web, for example `ios-simulator/arm64`. For iOS it
also excludes the x86_64 simulator slice and adds the camera and photo usage
descriptions, none of which `flutter create` provides.

For Android, a clean checkout needs only Dart, Flutter and the Android SDK:

```sh
dart run tool/gallery_builder/bin/prepare_gallery.dart --target android/arm64
cd gallery
flutter run -d <device-id> --release
```

The Dart preparer downloads and verifies every required model, generates the
gallery assets and configuration, and fails rather than building an incomplete
APK. `flutter run` builds, installs and launches the release app on the
connected phone; the APK remains at `gallery/build/app/outputs/flutter-apk/app-release.apk`.
It selects Google's released vision SDK and its Flutter plugin. Face Landmarker
and Hand Landmarker support CPU and GPU, with Android YUV camera conversion.
A physical Pixel 7 Test Lab run validates both delegates and front/back camera capture; see
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
`gstreamer1.0-plugins-good` in addition to Flutter's desktop dependencies, and
video file mode needs `gstreamer1.0-libav` to decode H.264.

## What decides the tiles

Three gates, in order:

1. **Bundled**: the preparer selects the tasks whose runtime this target can
   actually obtain. `tool/prepare.py` reads them from `sdk_downloads.dart`;
   `tool/gallery_builder` lists Android's and macOS's, and its tests check the
   macOS list against `sdk_downloads.dart`. EmbeddingGemma, the Proofreader
   and the Summarizer (419 MB of models) are bundled only when `--tasks` names
   them, as the simulator, emulator and browser test builds do, with Google's
   references for their suite from `--modern-text-reference` or the text
   package's checked-in fixtures. Bundled, they are tiles like the classic
   text tasks: EmbeddingGemma everywhere, the Proofreader and Summarizer
   wherever Google's runtime has them, so a browser shows their cards.
2. **Validated**: `lib/catalog.dart` asks the package's own capability query.
   Nothing restates support by hand, so a task validated on a new platform
   appears here with no code change.
3. **Demonstrable**: a screen of its own, which is what `GalleryDemo` names.
   Entries without one are known to the gallery but never become tiles.

Tasks without a validated runtime or a screen do not appear as tiles. The
package's status table below records their support details.

The visible tiles depend on the target and follow the package's
[status table](../packages/mediapipe-task-vision/tool/VISION_TASKS_STATUS.md):
each validated task with a screen appears, including the MagicTouch stroke
editor wherever its runtime runs.

## Live camera

`lib/live/` shares camera capture, live stream inference, timings, camera
switching, stop/start, cleanup and overlay geometry across live tasks. Every
camera frame is stamped when it arrives and submitted to the task in live
stream mode, which runs one frame at a time with the newest one waiting and
drops the rest, as Google's live stream does; native frames are converted only
when the task starts them (`VisionImage.deferred`), browser frames when they
arrive; the Stats card shows the
inference time and the frames dropped per second. It handles desktop RGBA,
Apple BGRA and Android YUV camera buffers. Every camera-based vision page also
has a **Mode** selector. Choose **Still image** to open a JPG, PNG or WebP file
and run IMAGE-mode inference with the same model, settings and CPU/GPU
delegate. Choose **Video file** to run a clip through the task in video mode:
every frame in order, with the file's own timestamps and rotation, a bundled
three-second clip (`samples/scene.mp4`) or a file you pick. Play, pause and
restart only, since video mode's timestamps cannot go back. The frames come
from `packages/video_frames`, the gallery's own plugin over each platform's
decoder: AVFoundation on iOS and macOS, MediaCodec on Android, Media
Foundation on Windows, GStreamer on Linux, and in browsers a `<video>` element
stepped one frame at a time. The vision package decodes nothing.
Switching back to **Camera** reopens the live stream task. Interactive Segmenter is image-only and uses its own editor.
Windows exposes CPU only. Face and Hand Landmarker also expose GPU on Linux,
Apple platforms, Android and web.
Web uses browser-native capture and transferable bitmaps while sharing these
controls and the same overlay painter. Web GPU requires worker WebGL 2 support.

## Tests

```sh
cd gallery
flutter test -d macos integration_test/assets_test.dart
flutter test -d macos integration_test/runtime_test.dart
flutter test -d macos integration_test/vision_still_image_modes_test.dart
```

Run one file per invocation: `flutter test -d macos integration_test/` cannot
start a second app instance on the device and fails to load the later file.

These check the bundle the app was actually built with: that every visible tile
can load its model and sample, that the live demo's model resolves, and that
all ten camera vision demos process their sample in still image mode. The
tests derive their asset names from the catalog, so they cannot drift from
what the screens ask for.

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
exposure, so a manual pass remains useful: run the gallery's Face Landmarker page
to check capture, preview mirroring and visual landmark alignment.
