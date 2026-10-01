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
