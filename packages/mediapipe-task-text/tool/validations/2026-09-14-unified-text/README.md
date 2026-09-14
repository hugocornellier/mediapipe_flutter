# MediaPipe 1.0.1 text migration validation

Validated on macOS 26.4 arm64 with Flutter 3.44.8 / Dart 3.12.2, CPU.

- All 26 official BERT/USE/language cases passed from paths and model buffers
  (52 comparisons), including full vectors, multilingual/empty text, label
  filtering, normalization and exact quantized bytes.
- Four cosine comparisons and four official creation errors matched. Native
  classifier timestamps and request order matched independent Python sequences.
- All 44 text package tests passed, covering invalid-model startup, disposal during initialization,
  queue draining, post-disposal rejection, repeated close, reusable option
  snapshots, struct layout and values surviving native free.
- 32 EmbeddingGemma/Proofreader/Summarizer regression tests and 37 core tests
  passed. The original demo's two widget tests and three native macOS UI tests
  passed, including USE reconfiguration and similarity.
- The fresh Flutter consumer passed debug and release with all nine tasks
  alive together. It bundled exactly one 1.0.1 runtime, one callback adapter
  and the two face libraries. No 2024 text library or duplicate Objective-C
  class was loaded. Bazel, CMake, Ninja and Python were blocked in child builds.

`report.json` is the fresh consumer's release report. Its timings come from
functional checks and are not controlled performance benchmarks.

Reproduce with `make models_text test_text test_core`, the commands in the
text examples' READMEs, and `make test_embedding_macos`. The shared runtime and
models come from the same public, checksum-verified sources consumers use.
