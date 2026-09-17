# MediaPipe Gallery

One app that opens every MediaPipe task this repository has validated on the
platform you run it on. A task appears as a tile only when its runtime is
bundled, its support is validated here, and a demo exists for it.

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
description, none of which `flutter create` provides.

## What decides the tiles

Three gates, in order:

1. **Bundled** — `tool/prepare.py` reads `sdk_downloads.dart` and selects the
   tasks whose runtime this target can actually obtain. Unpublished runtimes
   count only when a maintainer build is present in the package.
2. **Validated** — `lib/catalog.dart` asks the package's own capability query.
   Nothing restates support by hand, so a task validated on a new platform
   appears here with no code change.
3. **Demonstrable** — a runner in `lib/runners.dart`, or a live page.

Anything bundled but not validated, and anything validated without a demo, is
listed in the about sheet with the package's own reason rather than hidden.

Today that means 11 runtimes bundle on macOS, Linux and Windows, two on the iOS
simulator and Android, while hand, gesture, pose, holistic and the segmenters
stay off the grid pending the numerical work in `upstream-issues.md` UP-004.

## Live camera

`lib/live/` is the face camera controller and mesh overlay from
[the face example](../packages/mediapipe-task-vision/example), reused rather
than reimplemented. The only change is that `start()` takes the model asset key
from its caller, since the gallery bundles models under `assets/models/`.
The live tile is macOS-only until the camera path is exercised elsewhere.

## Tests

```sh
cd gallery && flutter test -d macos integration_test/assets_test.dart
```

These check the bundle the app was actually built with: that every visible tile
can load its model and sample, and that the live demo's model resolves. Both
derive their asset names from the catalog, so they cannot drift from what the
screens ask for.
