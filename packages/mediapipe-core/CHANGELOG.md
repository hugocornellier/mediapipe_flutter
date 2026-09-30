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
