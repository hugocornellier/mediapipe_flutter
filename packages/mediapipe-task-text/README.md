# MediaPipe Text for Flutter

`mediapipe_flutter_text` provides text classification, embedding, and language
detection through MediaPipe's native task pipelines. It is part of the private
[mediapipe_flutter](../../README.md) fork and is not published to pub.dev.

## Baseline and platforms

Use Flutter 3.44.8 stable / Dart 3.12.2. Native libraries download automatically
during builds, with caching and SHA-256 verification. No experimental flags are
needed.

All three tasks have executor and public API inference tests on macOS arm64.
Artifacts also exist for macOS x64, Android arm64, and iOS arm64 devices, but
those targets have not been revalidated. iOS simulators, Windows, Linux, and web
have no task runtime here.

The native libraries are the pinned 2024 upstream builds. Updating build tooling
has not changed the MediaPipe runtime or models.

## Models and local dependencies

Use the local dependencies in `example/pubspec.yaml`. There is no pub.dev release
of these renamed packages yet.

Applications supply model files separately, either as Flutter assets or as local
files. Include only the models your application uses. From the repository root,
`make get models` installs the dependencies and downloads the pinned models used
by the tests and example:

- [BERT classifier, version 1](https://storage.googleapis.com/mediapipe-models/text_classifier/bert_classifier/float32/1/bert_classifier.tflite)
- [Language detector, version 1](https://storage.googleapis.com/mediapipe-models/language_detector/language_detector/float32/1/language_detector.tflite)
- [Universal Sentence Encoder, version 1](https://storage.googleapis.com/mediapipe-models/text_embedder/universal_sentence_encoder/float32/1/universal_sentence_encoder.tflite)

Declare bundled models under `flutter.assets` in the application's pubspec, as
the example does. A model's Flutter asset key is not a filesystem path: load its
bytes and use `fromAssetBuffer`, or pass a real file path to `fromAssetPath`.

## Usage

```dart
import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_text/mediapipe_flutter_text.dart';

final data = await rootBundle.load('assets/bert_classifier.tflite');
final classifier = TextClassifier(
  TextClassifierOptions.fromAssetBuffer(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  ),
);
final result = await classifier.classify('Hello, world!');
print(result.classifications.first);
result.dispose();
classifier.dispose();
```

`LanguageDetector.detect` and `TextEmbedder.embed` follow the same pattern.
`TextEmbedder.cosineSimilarity` compares native embeddings; keep both source
results alive until that future completes, then dispose of them.

This baseline validates successful inference. Inherited isolate error propagation
and native-memory lifecycle edge cases still need an audit before publishing.

## Example and tests

From the repository root:

```sh
make get
make models
make test_text
make example_text
```

`make ci` runs analysis, formatting checks, tests, and a macOS example build.
