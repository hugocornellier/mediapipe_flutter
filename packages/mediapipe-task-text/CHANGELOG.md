## 0.2.0

- Breaking: every task is one class with the same API on every platform,
  created with `await Xxx.create(options)`, and `mediapipe_text.dart` is the
  only app library. See MIGRATION.md.
- Breaking: options are flat on core's `TaskOptions` (`model`, `modelPath`,
  `modelBytes`, `delegate`) with Google's settings; `baseOptions`,
  `classifierOptions`, `embedderOptions`, `fromAssetPath` and
  `fromAssetBuffer` are gone.
- Breaking: EmbeddingGemma is a `TextEmbedder` with
  `TextModels.embeddingGemma`: `embed(text, {formatContext})`, with Google's
  `EmbeddingType`, `TextRole` and `TextFormatContext`.
- Breaking: results are plain values on core's `Classifications`, `Embedding`
  and `MediaPipeCategory`, without `dispose`; `timestampMs` is
  `timestampMilliseconds`. `TextEmbedder.cosineSimilarity` is static.
- Breaking: per-task capability queries replace `TextTask` and
  `queryTextTaskCapabilities`; `queryTextEmbedderCapabilities` takes the
  model. `TextDelegate` and `TextTaskException` are core's `Delegate` and
  `TaskException`.
- Invalid classifier settings fail in Dart on every platform, and `create`
  refuses the GPU, which no text task runs on.

- `TextModels.byName` names every pinned model for
  `hooks.user_defines.mediapipe_text.models`, which
  `dart run mediapipe_core:bundle_models` bundles into the app.
- Breaking: `model:` uses the app's bundled copy and no longer downloads at
  run time unless `ModelStore.allowDownloads` is true.

## 0.1.0

First release under Google's name since `mediapipe_text` 0.0.1; see
MIGRATION.md.

- Text Classifier, Text Embedder and Language Detector on every platform, and
  EmbeddingGemma, Proofreader and Summarizer on macOS arm64, through Google's
  official runtimes.
- `XxxOptions(model: TextModels.bertClassifier)` downloads Google's pinned
  model on first use; app-supplied paths and bytes still work.
- `await XxxTask.create(options)` and idempotent `dispose()`; failures are
  `TextTaskException` or core's shared exception types.
- On Android, a task made from model bytes keeps them until it closes, since
  Google's SDK reads them in place (UP-033 in upstream-issues.md).
