# Core API migration

## 0.1.0 to 0.2.0

Apps import their family's library, which re-exports
`package:mediapipe_core/mediapipe_core.dart`. Plugins and family packages use
`package:mediapipe_core/platform_interface.dart`.

| 0.1.0 | 0.2.0 |
| --- | --- |
| `capabilities.dart`, `model_store.dart`, `mediapipe_exception.dart`, `web_runtime.dart` | `mediapipe_core.dart` |
| `VisionDelegate`, `TextDelegate`, `AudioDelegate` | `Delegate` |
| `TaskCapabilities<D>` | `TaskCapabilities` (non-generic) |
| `VisionTaskException`, `TextTaskException`, `AudioTaskException` | `TaskException` (`statusCode`, `gpuUnavailable`) |
| `DownloadException` | `ModelDownloadException` |
| `ModelStore(directory: Directory(...))` | `ModelStore(cacheDirectory: '...')` |
| `ModelStore.get` and `find` returning a `File` (native) or bytes (web) | A `ModelSource` with `path` (native) or `bytes` (web) |
| `io.dart` and `interface.dart` (the FFI-era containers, kept for `mediapipe_genai`) | Removed with `mediapipe_genai`; use the shared value types |
| FFI-era `BaseOptions`, `ClassifierOptions`, `EmbedderOptions`, `Category`, `Classifications`, `Embedding` on the main library | Removed from the app API; the shared value types `MediaPipeCategory`, `Classifications` and `Embedding` replace the containers |
| Each family's options base | `TaskOptions` (`model`, `modelPath`, `modelBytes`, `delegate`) |

## Before 0.1.0

| Before | Now |
| --- | --- |
| Package `mediapipe_flutter_core`, `import 'package:mediapipe_flutter_core/mediapipe_flutter_core.dart'` | Package `mediapipe_core`, `import 'package:mediapipe_core/mediapipe_core.dart'`; build settings move to `hooks.user_defines.mediapipe_core` |
| `package:mediapipe_core/io.dart` for app model options | `package:mediapipe_core/mediapipe_core.dart` |
| Separate download helpers | `ModelStore().get(DownloadAsset(...))` |
| A separate exception class per task | Catch `MediaPipeException`. Its subtypes: `RuntimeUnavailableException` (the platform or build settings cannot run the task; `fix` says what to change), `ModelDownloadException`, and one native failure type per family (`VisionTaskException`, `TextTaskException`, `AudioTaskException`). |
| Import FFI helpers from the primary library | Not public: they left with `io.dart` in 0.2.0. |

`ModelStore.get` returns a verified `File` on native platforms and verified
bytes in browsers. A task's `model:` option resolves a pinned model on first
creation. A task future cannot stop an in-flight native call. `Future.timeout`
limits how long the caller waits; `dispose()` drains work already accepted by
the task.
