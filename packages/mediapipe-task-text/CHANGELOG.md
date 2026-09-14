## Unreleased

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
- Keep the inherited 2024 text runtime as the default; modern runtime selection
  excludes it because the two generations cannot coexist in one app.

## 0.0.1

- Initial version.
