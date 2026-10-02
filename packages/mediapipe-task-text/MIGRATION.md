# Text API migration

## 0.1.0 to 0.2.0

Every task is now one class with the same API on every platform, created with
`await Xxx.create(options)`. Import only
`package:mediapipe_text/mediapipe_text.dart`; it re-exports everything shared
from `mediapipe_core`.

| 0.1.0 | 0.2.0 |
| --- | --- |
| `capabilities.dart`, `embedding_gemma.dart`, `interface.dart`, `io.dart`, `text_proofreader.dart`, `text_summarizer.dart`, `universal_mediapipe_text.dart`, `web_runtime.dart` | `mediapipe_text.dart` (plugins: `platform_interface.dart`) |
| `TextClassifier(options)`, `TextEmbedder(options)`, `LanguageDetector(options)` | `await TextClassifier.create(options)` and so on |
| `TextClassifierOptions(baseOptions: BaseOptions.path(p))`, `.fromAssetPath(p)` | `TextClassifierOptions(modelPath: p)` (likewise for every text task) |
| `BaseOptions.memory(bytes)`, `.fromAssetBuffer(bytes)` | `modelBytes: bytes` |
| `classifierOptions: ClassifierOptions(maxResults: 3, ...)` | `maxResults: 3, scoreThreshold: ..., displayNamesLocale: ..., categoryAllowlist: ..., categoryDenylist: ...` on the options |
| `embedderOptions: EmbedderOptions(l2Normalize: ..., quantize: ...)` | `l2Normalize: ..., quantize: ...` on `TextEmbedderOptions` |
| `EmbeddingGemma.create(EmbeddingGemmaOptions(model: TextModels.embeddingGemma))` | `TextEmbedder.create(TextEmbedderOptions(model: TextModels.embeddingGemma))` |
| `embed(text, context: ...)` | `embed(text, formatContext: ...)` |
| `EmbeddingTaskType` | `EmbeddingType` (Google's name) |
| `TextEmbeddingResult`, `TextEmbedding` (`floatValues`, `quantizedValues`, `dimensions`) | `TextEmbedderResult`, `Embedding` (`floatEmbedding`, `quantizedEmbedding`, `length`) |
| `await embedder.cosineSimilarity(a, b)`, `TextEmbedding.cosineSimilarity`, `textEmbeddingCosineSimilarity` | `TextEmbedder.cosineSimilarity(a, b)` (static, synchronous) |
| `Category`, `Classifications` (an `Iterable`) | `MediaPipeCategory`, `Classifications` (an unmodifiable `List`) |
| `Embedding.float(...)`, `Embedding.quantized(...)`, `type`, `isFloat`, `isQuantized` | `Embedding(floatEmbedding: ...)` or `Embedding(quantizedEmbedding: ...)`; test which is non-null |
| `result.timestampMs` | `result.timestampMilliseconds` |
| `result.dispose()`, `isClosed` | Removed; results are plain values |
| `TextDelegate` | `Delegate`; every task's options take `delegate` |
| `TextTaskException` | `TaskException` |
| `TextTask`, `queryTextTaskCapabilities`, `textTaskCapabilitiesForPlatform`, `queryEmbeddingGemmaCapabilities` | `queryTextClassifierCapabilities()`, `queryTextEmbedderCapabilities([model])`, `queryLanguageDetectorCapabilities()`, `queryTextProofreaderCapabilities()`, `queryTextSummarizerCapabilities()` and their `ForPlatform` forms |

Behavior that changed:

- Invalid classifier settings (`maxResults: 0`, both lists) throw
  `ArgumentError` in Dart on every platform, before Google's runtime sees
  them.
- `create` refuses a delegate the capability query rules out with
  `RuntimeUnavailableException`; the classic tasks run on CPU only.
- The Proofreader and Summarizer take `model` or `modelPath`, not
  `modelBytes`.
- `proofreadStream` and `summarizeStream` report a disposed task or invalid
  text as a stream error instead of throwing at the call.
- A format context passed to a browser or Android embedder throws
  `RuntimeUnavailableException`; Google's SDKs there take none.

## Before 0.1.0

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
