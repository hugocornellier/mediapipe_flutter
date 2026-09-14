# MediaPipe Text for Flutter

`mediapipe_flutter_text` provides text classification, embedding, and language
detection through MediaPipe's native task pipelines. It is part of the public
[mediapipe_flutter](../../README.md) fork and is not published to pub.dev.

## Baseline and platforms

Use Flutter 3.44.8 stable / Dart 3.12.2. Native libraries download automatically
during builds, with caching and SHA-256 verification. No experimental flags are
needed.

All three tasks have executor and public API inference tests on macOS arm64.
Artifacts also exist for macOS x64, Android arm64, and iOS arm64 devices, but
those targets have not been revalidated. iOS simulators, Windows, Linux, and web
have no task runtime here.

The existing `TextClassifier`, `TextEmbedder` (USE), and `LanguageDetector` APIs
use pinned 2024 upstream builds. **EmbeddingGemma** uses the official 1.0.1 runtime
on macOS arm64 CPU, macOS 14+. The runtime generations are mutually exclusive in
one app: native C++/Objective-C collisions were observed when loading both.
Selecting the modern runtime automatically omits the legacy library; inherited
task constructors then fail immediately with an explanatory error.

## EmbeddingGemma 300M

The new `EmbeddingGemma` API runs Google's complete official TextEmbedder
pipeline: task prompt formatting, SentencePiece tokenization, inference and
postprocessing. Model bytes and native inference code are unchanged. It returns
owned, immutable 768-value vectors; results need no `dispose`.

Enable the shared runtime in the **consuming app's** pubspec:

```yaml
hooks:
  user_defines:
    mediapipe_flutter_core:
      tasks_runtime: true
```

The build hook downloads and verifies the public native archive automatically.
MagicTouch uses this same native asset, bundled once even when both packages are
used. Face-only apps do not download it. The immutable archive retains its
historical `interactive-segmenter-v1.0.1-1` release name; it contains Google's full
1.0.1 task library (32.6 MB compressed, 100.9 MB unpacked).

Download the separate, pinned 183.8 MB model with
`dart tool/download_embedding_gemma.dart`. Applications can use the public
`embeddingGemmaModel` URL/checksum from `package:mediapipe_flutter_text/models.dart`
with core's `downloadVerified`, or bundle the model as a Flutter asset. See
[Gemma Terms](https://ai.google.dev/gemma/terms) for the model's license.

```dart
import 'package:mediapipe_flutter_text/embedding_gemma.dart';

final task = await EmbeddingGemma.create(
  EmbeddingGemmaOptions(modelPath: '/path/to/embedding_gemma.task'),
);
try {
  final context = TextFormatContext(
    taskType: EmbeddingTaskType.semanticSimilarity,
  );
  final a = await task.embed('A cat is sleeping.', context: context);
  final b = await task.embed('A kitten is resting.', context: context);
  print(TextEmbedding.cosineSimilarity(
    a.embeddings.single, b.embeddings.single,
  ));
} finally {
  await task.dispose();
}
```

All eight official formatting modes are supported, including retrieval documents
with titles and query/document roles. Omitting `context` passes a null pointer to
Google's API. CPU is the default; requesting GPU throws instead of silently
falling back. `l2Normalize` and `quantize` pass through to Google's postprocessor.
Both default to false. Quantized results retain Google's raw signed-int8 bytes.

Creation and inference run on a persistent isolate. Concurrent calls are queued;
awaiting `dispose` drains them and waits for worker exit. Prefer `modelPath` for
large models to avoid copying bytes. Embedded NUL characters are rejected before
crossing the C-string API. The task has a 512-token limit including its formatting
and special tokens: no automatic truncation or chunking is added. An upstream
graph failure can also make Google's native close operation fail; its error is
propagated, and the worker exits. Native cleanup is not guaranteed if Google's
close fails. Do not reuse a task after such an error.

From the repository root:

```sh
make models_embedding
cd packages/mediapipe-task-text/example_embedding
flutter pub get
dart test --reporter expanded
flutter test -d macos integration_test/demo_test.dart --reporter expanded
```

`make example_embedding` launches the sentence comparison demo.
`make test_embedding_macos` creates an isolated consumer, downloads all selected
models/runtimes, and checks official embeddings plus simultaneous face/mesh and
MagicTouch inference in debug and release. Bazel, CMake, Ninja and Python are
blocked during consumer builds. CI runs this validation and publishes its logs.
Proofreader and Summarizer are not implemented yet.

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
