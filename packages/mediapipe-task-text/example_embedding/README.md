# Sentence comparison and proofreading

Uses Google's official version 1 EmbeddingGemma 300M model and MediaPipe 1.0.1
TextEmbedder pipeline plus the official Proofreader 200M model on macOS arm64
CPU (macOS 14+). The Proofreader tab streams corrected text and highlights
Google's native insertion/deletion segments. From the repo root:

```sh
make models_embedding
make models_proofreader
cd packages/mediapipe-task-text/example_embedding
flutter pub get
flutter run -d macos --release
```

`make example_embedding` also downloads/verifies both models and launches the app.
The native runtime downloads automatically from the pinned public GitHub release.
Xcode's Clang builds the small native streaming adapter; no Bazel, CMake, Python
runtime or model conversion is required.

`dart test` compares 17 embedding and nine proofreading reference cases and
checks result ownership, errors, cancellation and lifecycle.
`flutter test -d macos integration_test/demo_test.dart` exercises both tabs,
including streaming and completed proofreading with highlighted edits.
