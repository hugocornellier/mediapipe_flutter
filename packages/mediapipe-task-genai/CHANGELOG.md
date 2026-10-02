## 0.0.1

Unpublished and unvalidated: the 2024 LLM Inference wrapper kept from the
original `mediapipe_genai` while the text, vision and audio packages were
rebuilt. Read the README before depending on it.

- `LlmInferenceEngine` streams responses from a model the app downloads
  itself (Kaggle terms), with `LlmInferenceOptions.cpu` and
  `LlmInferenceOptions.gpu` for the two model variants.
- The native hook downloads pinned, checksum-verified 2024 runtimes for macOS
  arm64, Android arm64 and iOS arm64 devices. There are no simulator, Intel
  macOS, Linux, Windows or web artifacts.
- No Summarizer, Proofreader or `.litertlm` support. Native inference is not
  validated on the Flutter 3.47.5 baseline; the example's tests cover Dart
  state only.
