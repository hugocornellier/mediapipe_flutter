# MediaPipe Gallery

One app for the interactive MediaPipe demos this repository supports on the
platform you run it on. A task appears as a tile only when its runtime is
bundled, its support is validated here, and it has a screen to show.

## Running it

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

## What decides the tiles

Three gates, in order:

1. **Bundled** — `tool/prepare.py` reads `sdk_downloads.dart` and selects the
   tasks whose runtime this target can actually obtain. Unpublished runtimes
   count only when a maintainer build is present in the package.
2. **Validated** — `lib/catalog.dart` asks the package's own capability query.
   Nothing restates support by hand, so a task validated on a new platform
   appears here with no code change.
3. **Demonstrable** — a screen of its own, which is what `GalleryDemo` names.
   Entries without one are known to the gallery but never become tiles.

Anything bundled but not validated, and anything validated without a screen, is
listed in the about sheet with the package's own reason rather than hidden.

Today that leaves two tiles on macOS: the live Face Landmarker and MagicTouch.
Everything else is bundled and reported but not demonstrated, either because it
has no screen yet or because it waits on the numerical work in
`upstream-issues.md` UP-004.

## Live camera

`lib/live/` is the Face Landmarker camera controller and landmark overlay from
[the face example](../packages/mediapipe-task-vision/example), reused rather
than reimplemented. The only change is that `start()` takes the model asset key
from its caller, since the gallery bundles models under `assets/models/`.
The live tile is macOS-only until the camera path is exercised elsewhere.

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
