## Unreleased

- Migrate BERT TextClassifier, USE TextEmbedder and LanguageDetector to the shared
  MediaPipe 1.0.1 runtime on macOS 14+ arm64 CPU. All six text tasks now coexist
  with MagicTouch and both face tasks. Consumers must enable core.tasks_runtime.
- Preserve existing task constructors, add asynchronous create factories, and
  make task disposal awaitable/idempotent. Queue requests, propagate startup
  errors and copy results into owned Dart storage before freeing native output.
- Retire 2024 text binaries/bindings and their unvalidated mobile/Intel targets.
  Remove native allocation methods from options; low-level result pointers use
  the new ABI, and executor similarity accepts Dart embeddings.
- Verify 26 official model/option cases from paths and bytes, native timestamps,
  lifecycle behavior, fresh Flutter debug/release bundling and the original demo.
- Add official Summarizer 200M with completed/streaming TL;DR and key-points
  modes, a separate verified model download, macOS demo and reference tests.
- Share the worker queue, cancellation/disposal and native callback copies
  between Proofreader and Summarizer.
- Add official EmbeddingGemma 300M and Proofreader 200M on macOS arm64 CPU with
  one optional MediaPipe 1.0.1 runtime and separate verified model downloads.
- Add completed and streaming proofreading with owned text/corrections, queued
  workers and draining cancellation/disposal.
- Add macOS demos, official Python references and fresh debug/release consumer
  checks alongside MagicTouch and face tasks.

## 0.0.1

- Initial version.
