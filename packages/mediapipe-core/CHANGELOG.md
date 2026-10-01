## Unreleased

- Models are bundled with the app at build time.
  `dart run mediapipe_core:bundle_models` downloads the models an app lists
  under `hooks.user_defines.<family>.models`, verifies each against its pin,
  writes them into `assets/mediapipe/` and removes unlisted ones; `--check`
  verifies that folder in CI.
- Breaking: `model:` no longer downloads at run time by default. It uses the
  store's cache, then the app's bundled copy, and downloads only when
  `ModelStore.allowDownloads` is true. Otherwise task creation throws a
  `RuntimeUnavailableException` whose `fix` names the pubspec entry to add.
- `ModelStore.find` returns a cached or bundled model without using the
  network, and `resolvePinnedModel` takes the model's family and registry so
  that error can name the entry.

## 0.1.0

First release of this rewrite; Google's `mediapipe_core` 0.0.1 held only the
text tasks' shared containers.

- Bundles Google's MediaPipe engine once per app for every task family: an
  adapter over Google's iOS SDK, the official wheel libraries on Linux x64 and
  Windows x64, and Google's macOS arm64 library (opt-in with
  `tasks_runtime: true`, since it is about 95 MB).
- Verified downloads with mirror fallback and offline or internal sources
  (`hooks.user_defines.mediapipe_core.asset_source`).
- `ModelStore`: pinned models downloaded on first use, verified, cached and
  shared across isolates and processes; Cache Storage in browsers.
- `MediaPipeWebRuntime`: one setting for where browsers load Google's
  runtimes, every file checked against its pinned SHA-384, and
  `dart run mediapipe_core:web_runtime` to self-host them.
- `MediaPipeException`, `RuntimeUnavailableException` and
  `ModelDownloadException` shared by every family.
