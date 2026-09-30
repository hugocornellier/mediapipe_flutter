# Text API migration

| Before | Now |
| --- | --- |
| Package `mediapipe_flutter_text`, `import 'package:mediapipe_flutter_text/mediapipe_flutter_text.dart'` | Package `mediapipe_text`, `import 'package:mediapipe_text/mediapipe_text.dart'`; build settings move to `hooks.user_defines.mediapipe_text` |
| `mediapipe_text.dart`, `io.dart`, or task-specific imports | `mediapipe_text.dart` |
| `TextClassifier(options)` | `await TextClassifier.create(options)` |
| `TextEmbedder(options)` | `await TextEmbedder.create(options)` |
| `LanguageDetector(options)` | `await LanguageDetector.create(options)` |
| `baseOptions: BaseOptions.path(...)` or `.memory(...)` only | `model: TextModels.bertClassifier` (or the existing `baseOptions:` source) |
| A modern text task's `modelPath:` or `modelBytes:` only | `model: TextModels.embeddingGemma` (or one of the existing sources) |
| `EmbeddingGemmaException`, `TextProofreaderException`, `TextSummarizerException` | `TextTaskException` (a `MediaPipeException`) |
| `TextTaskException.status` | `TextTaskException.statusCode` |

Supply exactly one model source. `model:` downloads a verified pinned model on
first task creation. Catch `MediaPipeException` for runtime failures and
`ModelDownloadException` for download failures. Use the task-specific
`queryXxxCapabilities()` function to inspect delegates and unavailable reasons.

Inference futures cannot cancel in-flight native work. `Future.timeout` limits
caller waiting only; `dispose()` drains accepted calls and is idempotent.
