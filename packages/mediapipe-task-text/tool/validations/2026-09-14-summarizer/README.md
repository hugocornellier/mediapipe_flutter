# Summarizer macOS validation — 2026-09-14

Passed on macOS 26.4 arm64, Flutter 3.44.8 / Dart 3.12.2. Uses the official
MediaPipe 1.0.1 runtime and version-1 Summarization 200M two-mode model. Native
inference code, prompts, tokenization and model bytes are unchanged. The C
adapter copies temporary callback data into memory owned by the Dart receiver.

Validation performed:

- Captured ten completed and streaming reference cases with Google's original
  pinned Python wheel. TLDR/key-points paragraphs, Unicode, short inputs and a
  smaller token budget. Exact full-text comparison. Empty input is rejected in
  both modes and both APIs, preserving Google's message.
- All **32 modern text tests** passed: 13 Summarizer, ten Proofreader and nine
  EmbeddingGemma. Includes ABI layouts, native errors, cache options, result
  ownership, concurrent task instances, queueing, cancellation, pause and
  draining disposal. Also reran all **25 legacy text tests**, successfully.
- Both callback adapters passed the AddressSanitizer test, including foreign
  threads that overwrite/free source strings before Dart would read the copy.
- All **three macOS demo integration tests** passed. Summarizer switches from
  key-points streaming to completed TLDR output. Missed taps are fatal. The
  similarity and Proofreader tabs also passed after sharing the text workers.
- A fresh consumer passed **debug and release**. Only publishable package
  sources were copied. Native libraries and models came from verified public
  downloads. Checks cover all ten summarization, nine proofreading and 17
  embedding reference cases, four native empty-input failures, the full
  MagicTouch mask, one detected face and 478 face landmarks.
- All six tasks inferred while alive together. The release app bundles one
  full modern runtime, one callback adapter, and two face libraries. No legacy
  text library or duplicate Objective-C runtime classes. Bazel/Bazelisk, CMake,
  Ninja and Python were blocked during consumer builds; Xcode Clang compiled
  only the callback adapter.
- Text package/example analysis, formatting and `git diff --check` passed.

The [recorded report](report.json) contains the fresh release app's actual
output and the runner's debug/download/bundling checks. Raw local logs are in
`build/codex-tmp/embedding-consumer-_rz6g_lk/`; CI uploads consumer logs/reports.
Timings are functional-test samples, not a controlled benchmark. They include
the public async API, native processing and owned copies. No speedup claim is
made, and no GPU/mobile support for Summarizer is established by these tests.

Reproduce with `make test_embedding_macos`. For the demo and Dart tests, run
`make models_embedding models_proofreader models_summarizer`, then use
`example_embedding`. The shared worker extraction preserves Proofreader's API
and its cancellation/disposal behavior.
