# Model bundling

**Status:** phase 1 is implemented: models are downloaded at build time and
ship inside the app by default, and downloading at run time is opt-in. Phase 2,
where the build hook does the bundling itself, waits for Flutter's data assets
to reach stable. The code site for phase 2 carries a TODO pointing here;
`git grep -n "MODEL_BUNDLING.md"` lists it.

Related: [API_UNIFICATION.md](API_UNIFICATION.md) plans the public API this
builds on; its Models section defers to this document.

## Why

Bundled models make apps safer and more predictable:

- There is no wait on first use, and no download that can fail.
- The app works offline from its first launch.
- The app never contacts Google's servers for models. On native, an app that
  bundles everything needs no Android `INTERNET` permission or macOS network
  entitlement for MediaPipe.
- Each model is verified once, at build time, against its pinned SHA-256.

This is also how the maintainer's other detection packages, such as
`face_detection_tflite`, ship their models.

## Why not ship every model inside the packages

`face_detection_tflite` ships all 12 of its models (29 MB) inside the package,
so every app gets all of them. That doesn't scale here:

- vision's default models total about 110 MB, near pub.dev's 100 MB package
  limit, and every app using one vision task would carry all of them;
- text's classic models are about 31 MB, and the text generation models are
  118 to 184 MB each.

So each app lists the models it uses.

## How it works (phase 1)

### Selecting models

Each app lists its models per family in pubspec, next to the existing `tasks:`
setting. The names are the keys of `VisionModels.byName`, `TextModels.byName`
and `AudioModels.byName`, the snake_case form of the `XxxModels` constants:

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
`lib/src/model_bundler.dart`):

- reads the app's pubspec and fails on a family the app doesn't depend on,
  an unknown name (listing the valid ones), or a missing `assets/mediapipe/`
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

Every family resolves `model:` through core's `resolvePinnedModel`, which
looks for the model in this order:

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

## Decisions taken

1. **The default** is bundle only; run-time downloads are opt-in, since that
   is the safer default.
2. **File names** in `assets/mediapipe/` are SHA-256s, matching `asset_source`,
   with `manifest.json` mapping them to readable names.
3. **The opt-in switch** is `ModelStore.allowDownloads`, set in code before
   creating tasks.
4. **The web runtime** keeps its own command, `dart run
   mediapipe_core:web_runtime`. Bundled models are served from the app's own
   origin, but Google's JavaScript runtime still loads from jsDelivr unless the
   app self-hosts it.

## Verified (2026-10-01)

- Unit tests: core's `test/model_bundling_test.dart` covers the pubspec
  parsing, downloading, reuse, repair, pruning, `--check`, unknown names, the
  missing declaration, the store's bundled copy and the three outcomes of
  `model:`. Each family's `test/models_test.dart` checks that `byName` covers
  every pinned model.
- A fresh Flutter app depending on vision and audio by path ran the command
  against Google's real URLs: `face_detector` (0.2 MB) and `yamnet` (3.9 MB)
  were downloaded and named by hashes that match their pins, then reused,
  repaired after tampering, pruned and checked.
- The same app ran as a sandboxed macOS app without the network client
  entitlement: Face Detector found the face in a bundled photo, YAMNet
  classified a 440 Hz tone as "Sine wave", and an unbundled Face Landmarker
  failed with the fix naming `face_landmarker`. The same three checks passed
  on the iOS simulator and an Android API 31 emulator (arm64).
- In Chromium, with requests to Google's storage blocked, the web build
  verified both bundled models, refused the unbundled one, and found the face.
- macOS release, Android arm64, iOS simulator and web builds contain both
  models with matching hashes.
- The store's lock: 300 rounds of 8 isolates racing for one model each made
  one request and returned one path. The previous lock loop failed 13 of 20
  rounds, giving up when its owner released the claim mid-check.
- `packages/mediapipe-core/tool/test_bundled_models.py` repeats this in a
  fresh app built from the packages as pub.dev ships them, with one model per
  family (`face_detector`, `language_detector`, `yamnet`): the command
  downloads them, `--check` passes, a corrupted copy and a stale file are
  repaired and removed, the debug app runs the three models with every HTTP
  client refused, refuses the unbundled Face Landmarker and, with downloads
  on, downloads it at run time; then a release build ships exactly the three
  models and passes the offline checks from a copy of its bundle. It passed on
  macOS arm64. CI runs it on Linux x64 and Windows x64
  (`.github/workflows/bundled-models.yaml`), with core's store and bundling
  unit tests.

## Phase 2: the build hook does it

Once Flutter's data assets reach stable (they are only on the master channel
in Flutter 3.47), each family's build hook reads its own `models:` list and
bundles those files as data assets. The command and `assets/mediapipe/` then
retire, and the pubspec lists stay as they are.

Later, Dart's record-use feature could let release builds bundle exactly the
models their code references. The list would then only be needed for debug
builds, which record nothing.

## Not done yet

- The gallery and the vision example still prepare their models with their
  own tools; switching them to the command would exercise it in CI.
- CI runs a bundling app on Linux and Windows only. macOS runs the same
  script locally; iOS, Android and the web were checked by hand.
