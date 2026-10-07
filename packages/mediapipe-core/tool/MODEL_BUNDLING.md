# Model bundling

Phase 1 is done: apps list their models in pubspec, `dart run
mediapipe_core:bundle_models` downloads them at build time, and they ship
inside the app, with downloading at run time opt-in. Phase 2, where the build
hooks bundle the models themselves, is planned and waits on Flutter's data
assets reaching stable. Phase 1 was verified on 2026-10-01; the plan was
restored from git history (`git show 9383185:tool/MODEL_BUNDLING.md`) and
rechecked against the code on 2026-10-06 at `bbf198c`. Paths are from the
repository root. Check a finding again before building on it.

## Goal

Each family's build hook reads the app's `models:` list and bundles those
files as data assets, so `dart run mediapipe_core:bundle_models` and the
`assets/mediapipe/` folder retire. The pubspec lists stay as they are.

Bundled models make apps safer and more predictable:

- There is no wait on first use, and no download that can fail.
- The app works offline from its first launch.
- The app never contacts Google's servers for models. On native, an app that
  bundles everything needs no Android `INTERNET` permission or macOS network
  entitlement for MediaPipe.
- Each model is verified once, at build time, against its pinned SHA-256.

This is also how the maintainer's other detection packages, such as
`face_detection_tflite`, ship their models.

Shipping every model inside the packages does not scale. `face_detection_tflite`
ships all 12 of its models (29 MB), so every app gets all of them. Here, as
recorded on 2026-10-01, vision's default models total about 110 MB, near
pub.dev's 100 MB package limit, and every app using one vision task would
carry all of them; text's classic models are about 31 MB, and the text
generation models are 118 to 184 MB each. So each app lists the models it
uses.

## Today (phase 1)

### Selecting models

Each app lists its models per family in pubspec, next to the `tasks:` setting.
The names are the keys of `VisionModels.byName`, `TextModels.byName` and
`AudioModels.byName`, the snake_case form of the `XxxModels` constants:

```yaml
flutter:
  assets:
    - assets/mediapipe/

hooks:
  user_defines:
    mediapipe_vision:
      models: [face_landmarker, hand_landmarker]
    mediapipe_audio:
      models: [yamnet]
```

### The command

`dart run mediapipe_core:bundle_models`, run from the app's root
(`packages/mediapipe-core/bin/bundle_models.dart`, with its logic in
`packages/mediapipe-core/lib/src/model_bundler.dart`):

- reads the app's pubspec and fails on a family the app doesn't depend on, an
  unknown name (listing the valid ones), or a missing `assets/mediapipe/`
  declaration (printing the lines to add);
- reads each listed family's `byName` by running a generated program,
  `.dart_tool/mediapipe_core/bundle_models_registry.dart`, with the app's
  package configuration, since core cannot depend on the families;
- downloads each model from Google, or from `asset_source` when it is set,
  verifies its SHA-256, and writes it into `assets/mediapipe/` named by that
  SHA-256, reusing files that already match;
- removes SHA-named files that are no longer listed, and writes a readable
  `manifest.json`;
- with `--check`, changes nothing and exits nonzero when the folder doesn't
  match the lists, for CI.

### Run-time lookup

Every family resolves `model:` through core's `resolvePinnedModel`
(`packages/mediapipe-core/lib/src/pinned_model.dart`), which looks for the
model in this order:

1. **The store's cache.**
2. **The app's bundled copy**, read with `rootBundle` and verified against the
   pin. On native it is copied once into the cache, so tasks keep receiving a
   file path; Google's iOS SDK only accepts paths. On web its bytes are used
   directly.
3. **A download**, only when `ModelStore.allowDownloads` is true.

Otherwise task creation throws `RuntimeUnavailableException`. Its `fix` names
the pubspec entry to add (from the family's `byName`) and the command to run.
A bundled file that doesn't match its pin is refused with a fix that reruns
the command. `ModelStore.find` does steps 1 and 2 without the network; an
explicit `ModelStore.get` or `prefetch` may always download.

### Decisions taken

1. **The default** is bundle only; run-time downloads are opt-in, since that
   is the safer default.
2. **File names** in `assets/mediapipe/` are SHA-256s, matching
   `asset_source`, with `manifest.json` mapping them to readable names.
3. **The opt-in switch** is `ModelStore.allowDownloads`, set in code before
   creating tasks.
4. **The web runtime** keeps its own command, `dart run
   mediapipe_core:web_runtime`. Bundled models are served from the app's own
   origin, but Google's JavaScript runtime still loads from jsDelivr unless the
   app self-hosts it.

### Verified (2026-10-01)

- **Unit tests:** core's `test/model_bundling_test.dart` covers the pubspec
  parsing, downloading, reuse, repair, pruning, `--check`, unknown names, the
  missing declaration, the store's bundled copy and the three outcomes of
  `model:`. Each family's `test/models_test.dart` checks that `byName` covers
  every pinned model.
- **A fresh app** depending on vision and audio by path ran the command
  against Google's real URLs: `face_detector` (0.2 MB) and `yamnet` (3.9 MB)
  were downloaded and named by hashes that match their pins, then reused,
  repaired after tampering, pruned and checked.
- **Offline runs:** the same app ran as a sandboxed macOS app without the
  network client entitlement: Face Detector found the face in a bundled photo,
  YAMNet classified a 440 Hz tone as "Sine wave", and an unbundled Face
  Landmarker failed with the fix naming `face_landmarker`. The same three
  checks passed on the iOS simulator and an Android API 31 emulator (arm64).
  In Chromium, with requests to Google's storage blocked, the web build
  verified both bundled models, refused the unbundled one, and found the face.
- **Release builds:** macOS release, Android arm64, iOS simulator and web
  builds contain both models with matching hashes.
- **The store's lock:** 300 rounds of 8 isolates racing for one model each
  made one request and returned one path. The previous lock loop failed 13 of
  20 rounds, giving up when its owner released the claim mid-check.
- **As published:** `packages/mediapipe-core/tool/test_bundled_models.py`
  repeats this in a fresh app built from the packages as pub.dev ships them,
  with one model per family (`face_detector`, `language_detector`, `yamnet`).
  The command downloads them, `--check` passes, a corrupted copy and a stale
  file are repaired and removed, the debug app runs the three models with
  every HTTP client refused, refuses the unbundled Face Landmarker and, with
  downloads on, downloads it at run time. A release build then ships exactly
  the three models and passes the offline checks from a copy of its bundle. It
  passed on macOS arm64. CI runs it on Linux x64 and Windows x64
  (`.github/workflows/bundled-models.yaml`), with core's store and bundling
  unit tests.

## Phase 2: the build hooks bundle the models

Once data assets reach Flutter stable, each family's build hook reads its own
`models:` list and bundles those files as data assets. The hooks already
download and verify pinned files at build time for the runtimes, so the models
would go through the same verified download and `asset_source`. The command,
the `assets/mediapipe/` folder and its `flutter: assets:` declaration then
retire. The vision hook carries the TODO
(`packages/mediapipe-task-vision/hook/build.dart`); the text and audio hooks
would need the same change.

Later, Dart's record-use feature could let release builds bundle exactly the
models their code references. The list would then only be needed for debug
builds, which record nothing.

## Before starting

- **Data assets on stable:** in Flutter 3.47.5 they are still master only. The
  SDK's `packages/flutter_tools/lib/src/features.dart` defines `dartDataAssets`
  (`enable-dart-data-assets`) with only `master: FeatureChannelSetting(
  available: true)`. Record use (`enable-record-use`) is also behind a flag.
- **Run-time lookup:** `resolvePinnedModel` reads the bundled copy with
  `rootBundle` from `assets/mediapipe/`; data assets are read differently, so
  step 2 of the lookup changes with them.

## Not done yet

- The vision example still prepares its models with its own tool.
- The gallery moved to the command on 2026-10-06: its preparers write the
  `models:` lists and run `bundle_models`, and its demos pass the pins. Every
  gallery workflow (Android, iOS, macOS, Linux, Windows and the web) therefore
  builds with bundled models, beside the dedicated bundling app on Linux and
  Windows.
