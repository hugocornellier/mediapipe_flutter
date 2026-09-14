# EmbeddingGemma sentence comparison

Uses Google's official version 1 EmbeddingGemma 300M model and MediaPipe 1.0.1
TextEmbedder pipeline on macOS arm64 CPU (macOS 14+). From the repo root:

```sh
make models_embedding
cd packages/mediapipe-task-text/example_embedding
flutter pub get
flutter run -d macos --release
```

`make example_embedding` also downloads/verifies the model and launches the app.
The native runtime downloads automatically from the pinned public GitHub release.
No Bazel, CMake, Python runtime or model conversion is required.

`dart test` compares all 17 official reference cases and checks result ownership,
errors and lifecycle. `flutter test -d macos integration_test/demo_test.dart`
exercises the real sentence editor and comparison button.
