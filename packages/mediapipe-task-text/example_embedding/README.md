# Similarity, proofreading and summarization

Uses Google's official version 1 EmbeddingGemma 300M model and MediaPipe 1.0.1
TextEmbedder pipeline plus the official Proofreader 200M model on macOS arm64
CPU (macOS 14+). The Proofreader tab streams corrected text and highlights
Google's native insertion/deletion segments. Summarizer 200M supplies TL;DR and
key-points modes with completed or streamed output in a third tab. From the repo root:

```sh
make models_embedding
make models_proofreader
make models_summarizer
cd packages/mediapipe-task-text/example_embedding
flutter pub get
flutter run -d macos --release
```

`make example_embedding` downloads/verifies all three demo models and launches the app.
The native runtime downloads automatically from the pinned public GitHub release.
Xcode's Clang builds the small native streaming adapter; no Bazel, CMake, Python
runtime or model conversion is required.

`dart test` compares 17 embedding, nine proofreading and ten summarization cases and
checks result ownership, errors, cancellation and lifecycle.
`flutter test -d macos integration_test/demo_test.dart` exercises all three tabs,
including streaming/completed output, highlighted edits and summarization modes.
