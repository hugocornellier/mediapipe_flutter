## 0.1.0 (unreleased)

Not published yet. The first release of this rewrite, replacing Google's
`mediapipe_core` 0.0.1 (May 2024), which held only the shared containers of
Google's text package; [MIGRATION.md](MIGRATION.md) maps that API.

- The shared layer of every task family. `mediapipe_core.dart` is the one
  library apps see, through each family's library, which re-exports it;
  `platform_interface.dart` is for family packages and plugins.
- Bundles Google's MediaPipe engine once per app for every family: an adapter
  over Google's iOS SDK (including the Proofreader and Summarizer C API, over
  `MPPTextProofreader` and `MPPTextSummarizer`), the official wheel libraries
  on Linux x64 and Windows x64, and Google's macOS arm64 library (opt-in with
  `tasks_runtime: true`, since it is about 95 MB).
- An Android library, `dev.mediapipe.flutter.core`, that the family plugins
  build on: `TaskHost` runs Google's tasks on one worker thread, keeps their
  model buffers alive, answers the method channel and sends a streamed
  request's updates, and `TaskJson` shapes Google's classification and
  embedding containers as its JavaScript API does.
- Shared types: `TaskOptions` (the base of every options class, with `model`,
  `modelPath`, `modelBytes` and `delegate`), one `Delegate`,
  `TaskCapabilities`, and the value types `MediaPipeCategory`,
  `Classifications`, `Embedding`, `Detection`, `BoundingBox`,
  `NormalizedKeypoint`, `NormalizedLandmark`, `Landmark`, `Matrix`,
  `ConfidenceMask` and `CategoryMask`.
- Shared errors: `MediaPipeException`, with `RuntimeUnavailableException`
  (whose `fix` says what to change), `ModelDownloadException` and
  `TaskException`. `checkClassifierSettings` and `requireDelegate` give every
  family the same option checks and delegate refusal. Every classifier's
  options implement `ClassifierSettings`, which `classifierSettingsJson`
  names as Google's JavaScript API does, and `decodeClassifications`,
  `decodeEmbedding` and `decodeCategory` read the results the browser and
  Android adapters deliver.
- Models are bundled with the app at build time.
  `dart run mediapipe_core:bundle_models` downloads the models an app lists
  under `hooks.user_defines.<family>.models`, verifies each against its pin,
  writes them into `assets/mediapipe/` and removes unlisted ones; `--check`
  verifies that folder in CI. A task's `model:` uses the store's cache, then
  the app's bundled copy, and downloads only when `ModelStore.allowDownloads`
  is true; otherwise task creation throws a `RuntimeUnavailableException`
  whose `fix` names the pubspec entry to add.
- `ModelStore`: verified models cached and shared across isolates and
  processes, in Cache Storage in browsers. `get` and `find` return a
  `ModelSource` (`path` on native platforms, `bytes` in browsers), and `find`
  never uses the network.
- Verified runtime downloads with mirror fallback and offline or internal
  sources (`hooks.user_defines.mediapipe_core.asset_source`).
- `MediaPipeWebRuntime`: one setting for where browsers load Google's
  runtimes, every file checked against its pinned SHA-384, and
  `dart run mediapipe_core:web_runtime` to self-host them.
