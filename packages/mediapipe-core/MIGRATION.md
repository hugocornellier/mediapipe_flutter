# Core API migration

| Before | Now |
| --- | --- |
| Package `mediapipe_flutter_core`, `import 'package:mediapipe_flutter_core/mediapipe_flutter_core.dart'` | Package `mediapipe_core`, `import 'package:mediapipe_core/mediapipe_core.dart'`; build settings move to `hooks.user_defines.mediapipe_core` |
| `package:mediapipe_core/io.dart` for app model options | `package:mediapipe_core/mediapipe_core.dart` |
| Separate download helpers | `ModelStore().get(DownloadAsset(...))` |
| A separate exception class per task | Catch `MediaPipeException`. Its subtypes: `RuntimeUnavailableException` (the platform or build settings cannot run the task; `fix` says what to change), `ModelDownloadException`, and one native failure type per family (`VisionTaskException`, `TextTaskException`, `AudioTaskException`). |
| Import FFI helpers from the primary library | Import `io.dart` only in package implementation code. |

`ModelStore.get` returns a verified `File` on native platforms and verified
bytes in browsers. A task's `model:` option resolves a pinned model on first
creation. A task future cannot stop an in-flight native call. `Future.timeout`
limits how long the caller waits; `dispose()` drains work already accepted by
the task.
