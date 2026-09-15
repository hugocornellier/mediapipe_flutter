# MediaPipe Text for Flutter

`mediapipe_flutter_text` provides summarization, proofreading, classification, embedding, and language
detection through MediaPipe's native task pipelines. It is part of the public
[mediapipe_flutter](../../README.md) fork and is not published to pub.dev.

## Baseline and platforms

Use Flutter 3.44.8 stable / Dart 3.12.2. Native libraries download automatically
during builds, with caching and SHA-256 verification. No experimental flags are
needed.

All six text tasks use the same official **MediaPipe 1.0.1** runtime on
**macOS arm64 CPU, macOS 14+**: TextClassifier (BERT), TextEmbedder (Universal
Sentence Encoder), LanguageDetector, EmbeddingGemma, Proofreader and Summarizer.
They can run together with MagicTouch and both face tasks. The 2024 text runtime
has been retired; its unvalidated Android, iOS and Intel macOS artifacts are no
longer selected. Those platforms need a separate 1.0.1 integration.

Every text consumer must enable `hooks.user_defines.mediapipe_flutter_core.tasks_runtime: true`
in its app pubspec, as shown below. Models remain separate optional downloads.

## Capabilities and settings

Query support before offering a delegate in your app:

```dart
import 'package:mediapipe_flutter_text/capabilities.dart';

final support = await queryTextTaskCapabilities(TextTask.embeddingGemma);
final canUseCpu = support.supportedDelegates.contains(TextDelegate.cpu);
final gpuReason = support.unavailableReasons[TextDelegate.gpu];
```

Use `TextTask.proofreader` or `TextTask.summarizer` for those tasks. The result
includes the process platform, required OS/architecture, minimum OS version and
runtime version. This is declared package support; it does not load a model,
verify native-asset opt-in, or promise sufficient memory. Creation checks the
same support information and reports an unavailable delegate before loading.

All three currently support CPU only. Official 1.0.1 GPU probes show that
Proofreader and Summarizer explicitly accept only CPU. EmbeddingGemma reaches
Metal but fails to prepare its delegate with the official model. The
[validation/benchmark tool](../../tool/task_benchmarks/README.md) documents
reproduction, option coverage and recorded results.

The macOS demo exposes all eight embedding task formats, per-input query/document
roles and titles, normalization and quantization. Changes to inference options
recreate the task. Proofreader and Summarizer expose token-budget presets;
Summarizer also has both official modes. Token budgets include input and output:
an input that already exceeds the budget can return a native error. The package
does not silently truncate input. Streaming can be selected independently.

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
It also compiles a small callback-copy adapter with Xcode's Clang. No MediaPipe
source build, Bazel, CMake or Python installation is needed by consumers.
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
make models_proofreader
make models_summarizer
cd packages/mediapipe-task-text/example_embedding
flutter pub get
dart test --reporter expanded
flutter test -d macos integration_test/demo_test.dart --reporter expanded
```

`make example_embedding` launches similarity, proofreading and summarization tabs.
`make test_embedding_macos` creates an isolated consumer, downloads all selected
models/runtimes, and checks official embeddings plus simultaneous face/mesh and
MagicTouch inference in debug and release. Bazel, CMake, Ninja and Python are
blocked during consumer builds. CI runs this validation and publishes its logs.

## Proofreader 200M

`TextProofreader` runs Google's complete official pipeline, including model
formatting, tokenization, generation and the ordered correction segments from
Google's diff. It uses the same runtime opt-in above on macOS arm64 CPU, macOS
14+. GPU is rejected explicitly. The [official API guide](https://developers.google.com/edge/mediapipe/solutions/text/text_proofreader/python)
describes the upstream task.

Download the pinned 117.6 MB version-1 `.litertlm` model with
`dart tool/download_proofreader.dart`. The public `proofreaderModel` URL and
SHA-256 work with core's `downloadVerified` for app-managed downloads. Models
remain optional, separate files; enabling the runtime does not download them.

```dart
import 'package:mediapipe_flutter_text/text_proofreader.dart';

final task = await TextProofreader.create(TextProofreaderOptions(
  modelPath: '/path/to/proofread_quant_200m.litertlm',
));
try {
  final result = await task.proofread('She go home.');
  print(result.proofreadText);
  for (final edit in result.corrections) {
    print('${edit.type.name}: ${edit.text}');
  }
  await for (final update in task.proofreadStream('I recieved your mesage.')) {
    if (update.chunk != null) print(update.chunk);
    if (update.done) print(update.corrections);
  }
} finally {
  await task.dispose();
}
```

Chunks contain newly generated text. The final update normally has a null chunk
and the complete corrections. Each correction is `same`, `insertion` or
`deletion`, in native order; character-level edits are preserved. Results and
updates own their data and remain valid after disposal. No Dart diff or prompt
rewrite is applied.

The native callback's temporary buffers are copied in a small C adapter before
forwarding to Dart; Google's model and runtime code are unchanged. The worker
serializes regular and streaming requests. Streams start on listen and have one
subscription. Cancellation suppresses further delivery and **awaits native
completion** because the official API offers no cancellation operation. Pausing
buffers Dart updates. Await `dispose()` to drain queued work and close the task.

`maxNumTokens` and `cacheDirectory` pass through to Google's options. Null or
zero tokens selects the native default. Model paths and input strings must not
contain NUL. The wrapper propagates native errors without substituting output,
automatically truncating text or falling back to another backend.

Nine official Python references cover grammar, spelling, unchanged text,
punctuation, Unicode, empty input, a paragraph and a smaller token budget.
`example_embedding/test/text_proofreader_test.dart` checks both APIs, ABI,
cancellation, pause, queueing, errors and disposal. `make test_text_stream_bridge`
tests copying from a foreign thread under AddressSanitizer.
`make test_embedding_macos` also checks Proofreader in fresh Flutter debug and
release apps alongside EmbeddingGemma, MagicTouch and both face tasks, with one
shared runtime.

## Summarizer 200M

`TextSummarizer` runs Google's complete official pipeline on macOS arm64 CPU,
macOS 14+. It shares the runtime, worker queue and callback-copy infrastructure
with Proofreader. Both `TextSummarizerMode.tldr` and `.keypoints` pass directly to
Google's task; the default is key points. The [official guide](https://developers.google.com/edge/mediapipe/solutions/text/text_summarizer/python)
describes the upstream options. GPU is rejected explicitly.

The version-1 model is a separate 117.6 MB download. Use
`dart tool/download_summarizer.dart`, or the public `summarizerModel` URL/SHA-256
with core's `downloadVerified`. The [model overview](https://developers.google.com/edge/mediapipe/solutions/text/text_summarizer)
links its Gemma terms. Enabling the shared runtime does not download models.

```dart
import 'package:mediapipe_flutter_text/text_summarizer.dart';

final task = await TextSummarizer.create(TextSummarizerOptions(
  modelPath: '/path/to/summarization_quant_200m_2modes.litertlm',
  mode: TextSummarizerMode.tldr,
));
try {
  final result = await task.summarize(article);
  print(result.summary);
  await for (final update in task.summarizeStream(article)) {
    if (update.chunk != null) print(update.chunk);
    if (update.done) print('Finished');
  }
} finally {
  await task.dispose();
}
```

Mode is fixed at creation; recreate the task to switch modes. Google's output
is preserved, including bullet markers and whitespace. No custom prompt,
reformatting, chunking or additional truncation is applied. `maxNumTokens` and
`cacheDirectory` pass through to native options; null/zero tokens uses the native
default. Empty input returns Google's `TextSummarizerException`; both APIs remain
usable after that error. NUL characters are rejected before native calls.

Results and updates own their strings. Streams start on listen, accept one
subscription and deliver new chunks followed by a terminal update. Cancellation
waits for native completion while suppressing delivery; pausing buffers updates.
Await `dispose()` to drain queued requests and release the native task.

Ten Python reference cases cover both modes, paragraphs, Unicode, short text and
a smaller token budget. Empty-input errors are checked separately in both modes
and APIs. `example_embedding/test/text_summarizer_test.dart` also covers ABI,
ownership, parallel task instances, queueing, cancellation, pause and disposal.
`make test_embedding_macos` validates fresh debug/release apps and simultaneous
all six text tasks, MagicTouch, face detector and face mesh inference with one
shared 1.0.1 runtime.

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

`make models_text` downloads only these three models. Their public URL/checksum
pins are `bertClassifierModel`, `universalSentenceEncoderModel` and
`languageDetectorModel` in `package:mediapipe_flutter_text/models.dart`.

Declare bundled models under `flutter.assets` in the application's pubspec, as
the example does. A model's Flutter asset key is not a filesystem path: load its
bytes and use `fromAssetBuffer`, or pass a real file path to `fromAssetPath`.

## Usage

```dart
import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_text/mediapipe_flutter_text.dart';

final data = await rootBundle.load('assets/bert_classifier.tflite');
final classifier = await TextClassifier.create(
  TextClassifierOptions.fromAssetBuffer(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  ),
);
try {
  final result = await classifier.classify('Hello, world!');
  print(result.classifications.first);
} finally {
  await classifier.dispose();
}
```

`LanguageDetector.detect` and `TextEmbedder.embed` follow the same pattern.
`TextEmbedder.cosineSimilarity` compares owned vectors, including signed int8
quantized output. Results remain readable after subsequent inference or task
disposal. Result `dispose()` remains as an optional, idempotent compatibility
method; it does not release or invalidate any data.

## Migrating existing text callers

- Enable the shared runtime setting above; remove `legacy_runtime: true`.
- Existing `TextClassifier(options)`, `TextEmbedder(options)` and
  `LanguageDetector(options)` constructors still start a worker immediately.
  Prefer `await Task.create(options)` to receive initialization errors at creation.
- Await task `dispose()`. It drains accepted requests, releases the native task
  and waits for its isolate to exit. Repeated disposal returns the same future.
  Calls submitted after disposal begins fail with `StateError`.
- Model, configuration and native failures reach callers as `TextTaskException`
  with the official message and status when available. Invalid models no longer
  leave requests waiting on a dead worker. Embedded NUL is rejected before FFI.
- Options snapshot model bytes and classifier lists. They can be reused across
  tasks and no longer expose native `copyToNative`/`dispose` methods.
- Low-level executors now initialize synchronously and use the 1.0.1 ABI.
  Their results eagerly copy borrowed native data; the caller of a `.native`
  result constructor owns the supplied pointer. Executor `cosineSimilarity`
  accepts Dart embeddings instead of pointers. Old generated 2024 bindings and
  headers have been removed.

The official version-1 model files are unchanged. Runtime migration can change
floating-point scores slightly. No tokenizer, prompt, label ordering, threshold,
normalization or quantization is reimplemented in Dart. TextClassifier's native
timestamp is preserved, including its advance on repeated requests.

The pinned Python reference generator records 26 model/option cases, four
creation errors, cosine similarities and repeated-request sequences. Tests
compare every score/vector value from both path and buffer models, check the
1.0.1 struct layouts, and cover initialization failure, queue ordering, immediate
and repeated disposal, option snapshots and result ownership. Fresh Flutter
debug/release consumers run the same references and all nine tasks together.

## Example and tests

From the repository root:

```sh
make get
make models
make test_text
make example_text
```

`make ci` runs analysis, formatting checks, tests, and a macOS example build.
