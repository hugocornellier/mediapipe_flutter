# Proofreader macOS validation — 2026-09-14

Passed on macOS 26.4 arm64, Flutter 3.44.8 / Dart 3.12.2. Uses the official
MediaPipe 1.0.1 runtime and version-1 Proofreader 200M `.litertlm`; the model and
native inference pipeline are unchanged. The callback adapter only copies data.

Checks performed:

- Generated nine reference cases using Google's pinned Python wheel, for both
  completed and streaming calls. Exact text and correction-segment comparisons.
- Ten Proofreader Dart tests: ABI, explicit cache/zero token budget, references,
  queued mixed requests, draining disposal, cancellation, pause/resume,
  unlistened streams, invalid creation and invalid Dart inputs.
- Nine existing EmbeddingGemma tests and 25 legacy text tests passed.
- C callback adapter passed AddressSanitizer, including a foreign pthread whose
  source strings/arrays are overwritten and freed before the receiver reads.
- Two real macOS demo integration tests passed, covering sentence comparison,
  streamed proofreading, highlighted insertion/deletion spans, and switching to
  completed proofreading. Missed test taps are fatal.
- An isolated consumer copied only the publishable package sources, downloaded
  verified public runtimes/models, and passed in **debug and release**. It checks
  all nine Proofreader and 17 embedding reference cases, MagicTouch's full mask,
  one face and 478 landmarks. All five tasks also infer while alive together.
- The fresh consumer bundled one full MediaPipe 1.0.1 runtime, one small callback
  adapter, and the two face libraries. No legacy text library or duplicate
  Objective-C runtime classes. Bazel, Bazelisk, CMake, Ninja and Python were
  blocked during builds; system Clang compiled the callback adapter.
- Text package/example analysis, formatting and `git diff --check` passed.

The checked-in [report](report.json) is the fresh release app's actual output,
with debug success and packaging checks added by the runner. Local raw logs are
under `build/codex-tmp/embedding-consumer-0zcj14l_/`. CI uploads consumer logs and
reports. Reproduce with `make test_embedding_macos`; demo/reference tests run
from `example_embedding` after `make models_embedding models_proofreader`.

Timings are functional-test samples, **not a benchmark**. Other builds/tests ran
on the same Mac, causing substantial contention in some embedding samples.
The report retains all samples; no outliers were removed. No speedup claim is
made. This validation establishes macOS arm64 CPU support, not GPU or mobile
support for Proofreader.
