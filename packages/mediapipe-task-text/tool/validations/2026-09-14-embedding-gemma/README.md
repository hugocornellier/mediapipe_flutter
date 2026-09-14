# macOS CPU validation — 2026-09-14

`report.json` was produced by `tool/test_embedding_macos.py` on the maintainer's
Apple M4 Max, macOS 26.4, Flutter 3.44.8 / Dart 3.12.2. This is a functional
validation with short timings, not a controlled performance benchmark.

The runner creates a new Flutter app and copies only package `lib`, `hook`,
pubspec and native-download metadata. It downloads every selected model with
pinned SHA-256 verification, and the runtime through its normal public GitHub
Release build hook. Bazel, Bazelisk, CMake, Ninja and Python are blocked during
consumer builds. No local native build or Python installation is copied.

- Debug macOS integration test: passed all 17 official embedding references.
- Release app: passed the same references with maximum absolute error **0**.
- MagicTouch mask: maximum absolute error **0** while text and face tasks lived
  in the same process. Face Detector found one face and Landmarker returned 478
  points for the reference portrait.
- Exactly one `interactive_segmenter.framework` (the full 1.0.1 runtime) was
  bundled; no old `libtext` runtime. Its historical name is intentional.
- The calling isolate's timer continued ticking during inference. Concurrent
  text requests drained on disposal and their owned results remained valid.
- Legacy public constructors reject this configuration before spawning workers.

Additional local checks: 37 core tests, 25 legacy text tests, 127 vision tests,
9 modern embedding tests (including model bytes, quantization, ABI, ownership,
initialization errors and native token-limit/close failures), and the real demo's
macOS UI integration test passed.

The default legacy text configuration is intentionally separate. An early mixed
runtime regression run crashed during native subgraph registration and reported
duplicate Objective-C classes. The hooks now reject an explicit request to
bundle both text generations. No reference tolerance, pipeline or model was
changed to work around that collision.

Full local consumer logs are retained under
`build/codex-tmp/embedding-consumer-9kfy18tp/`. The macOS CI job uploads logs and
reports from fresh reruns; this report describes the local run only.
