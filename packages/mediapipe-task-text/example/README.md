# BERT, USE and language detection demo

Runs the official MediaPipe 1.0.1 pipelines on macOS 14+ arm64 CPU. From the
repository root, run `make models_text example_text`. The app bundles only the
three version-1 models selected in its pubspec and enables core's shared runtime.

The native UI tests classify text, detect Spanish, compare USE embeddings and
change embedding options. Run from this directory:

```sh
flutter test --reporter expanded
flutter test -d macos integration_test/text_tasks_test.dart --reporter expanded
```

The widgets close tasks they create when disposed and leave injected tasks to
their caller. Model creation failures are displayed rather than leaving an
inference request waiting indefinitely.
