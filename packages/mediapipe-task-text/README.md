# mediapipe_text

Google's MediaPipe text tasks for Dart and Flutter: text classification, text
embeddings and language detection on every platform, plus EmbeddingGemma,
Proofreader and Summarizer on macOS. Every task runs Google's official
MediaPipe pipeline, and Google's pinned models are bundled with your app at
build time.

> **Not on pub.dev yet.** Depend on it by path from a checkout of
> [the repository](https://github.com/hugocornellier/mediapipe_flutter) until
> it is published.

## Tasks and platforms

| Task | Class | Android | iOS | macOS arm64 | Linux x64 | Windows x64 | Web |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Text classification (BERT) | `TextClassifier` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Text embeddings (Universal Sentence Encoder) | `TextEmbedder` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Language detection | `LanguageDetector` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| EmbeddingGemma 300M | `EmbeddingGemma` | | | ✓ | | | |
| Proofreader 200M | `TextProofreader` | | | ✓ | | | |
| Summarizer 200M | `TextSummarizer` | | | ✓ | | | |

All text tasks run on the CPU. The runtimes are Google's: the Android SDK
(`tasks-text` 1.0.0), an adapter over the 1.0.1 iOS SDK (iOS 15+, devices and
the arm64 simulator), the official wheel libraries on Linux (1.0.1) and
Windows (1.0.0), Google's 1.0.0 library on macOS 14+, and
`@mediapipe/tasks-text` 1.0.1 in browsers. `mediapipe_core` bundles the
native engine once per app, shared with vision and audio.

On macOS, text tasks need Google's engine, which is opt-in because it adds
about 95 MB:

```yaml
hooks:
  user_defines:
    mediapipe_core:
      tasks_runtime: true
```

Other platforms need no setting. See
[platform setup](https://github.com/hugocornellier/mediapipe_flutter/blob/main/doc/platform_setup.md)
for permissions, Linux graphics libraries and self-hosting the browser
runtime.

## Quick start

```dart
import 'package:mediapipe_text/mediapipe_text.dart';

Future<void> classify() async {
  final classifier = await TextClassifier.create(
    TextClassifierOptions(model: TextModels.bertClassifier),
  );
  try {
    final result = await classifier.classify('Hello, world!');
    final top = result.classifications.first.categories.first;
    print('${top.categoryName}: ${top.score}');
  } finally {
    await classifier.dispose();
  }
}
```

`TextModels` names Google's model for every task (`bertClassifier`,
`universalSentenceEncoder`, `languageDetector`, `embeddingGemma`,
`proofreader`, `summarizer`). Bundle the ones your app uses at build time:
list them in its pubspec, declare the folder they go in, and run
`dart run mediapipe_core:bundle_models` from the app's root, which downloads
each once and checks it against its SHA-256:

```yaml
flutter:
  assets:
    - assets/mediapipe/

hooks:
  user_defines:
    mediapipe_text:
      models: [bert_classifier]
```

`TextModels.byName` lists the accepted names. A model that is not bundled
makes `create` throw a `RuntimeUnavailableException` naming the entry to add;
setting `ModelStore.allowDownloads = true` from `mediapipe_core` downloads it
at run time instead. The text generation models are 118 to 184 MB, so weigh
that against your app's size. To use your own
model, pass `TextClassifierOptions.fromAssetPath` (a file path) or
`.fromAssetBuffer` (bytes, for example from `rootBundle`); the modern tasks
take `modelPath` or `modelBytes`. Give exactly one model source.

Results own their data and stay valid after the task is disposed.

### Language detection

`LanguageDetector` returns language codes with probabilities, most likely
first.

```dart
import 'package:mediapipe_text/mediapipe_text.dart';

Future<void> detectLanguage(String text) async {
  final detector = await LanguageDetector.create(
    LanguageDetectorOptions(model: TextModels.languageDetector),
  );
  try {
    final result = await detector.detect(text);
    for (final prediction in result.predictions.take(3)) {
      print('${prediction.languageCode}: ${prediction.probability}');
    }
  } finally {
    await detector.dispose();
  }
}
```

### Text embeddings

`TextEmbedder` turns a sentence into a vector with the Universal Sentence
Encoder; `cosineSimilarity` compares two, including quantized ones. The
higher the value, the closer the meaning.

```dart
import 'package:mediapipe_text/mediapipe_text.dart';

Future<double> compareSentences(String first, String second) async {
  final embedder = await TextEmbedder.create(
    TextEmbedderOptions(model: TextModels.universalSentenceEncoder),
  );
  try {
    final a = await embedder.embed(first);
    final b = await embedder.embed(second);
    return await embedder.cosineSimilarity(
      a.embeddings.first,
      b.embeddings.first,
    );
  } finally {
    await embedder.dispose();
  }
}
```

## Behavior

- `create` reports initialization errors; each task runs on its own isolate
  and queues concurrent calls.
- `dispose()` drains accepted calls, releases the native task and waits for
  the isolate to exit. It is idempotent; calls after it throw `StateError`.
- Failures are `MediaPipeException`s: `RuntimeUnavailableException` (the
  platform or settings cannot run the task, with a `fix`),
  `ModelDownloadException`, and `TextTaskException` with Google's message and
  native `statusCode`.
- Input containing NUL characters is rejected before it reaches native code.
- Nothing is reimplemented in Dart: tokenization, prompts, label order,
  thresholds, normalization and quantization are Google's.

Query support before offering a task or delegate:

```dart
import 'package:mediapipe_text/mediapipe_text.dart';

Future<bool> canSummarize() async {
  final support = await queryTextSummarizerCapabilities();
  return support.supportedDelegates.contains(TextDelegate.cpu);
}
```

The result also carries the reason for every unavailable delegate. It
describes declared support; it does not load a model.

## EmbeddingGemma 300M

`EmbeddingGemma` runs Google's complete TextEmbedder pipeline: prompt
formatting, SentencePiece tokenization, inference and postprocessing. It
returns 768-value vectors.

```dart
import 'package:mediapipe_text/mediapipe_text.dart';

Future<double> similarity(String a, String b) async {
  final task = await EmbeddingGemma.create(
    EmbeddingGemmaOptions(model: TextModels.embeddingGemma),
  );
  try {
    final context = TextFormatContext(
      taskType: EmbeddingTaskType.semanticSimilarity,
    );
    final first = await task.embed(a, context: context);
    final second = await task.embed(b, context: context);
    return TextEmbedding.cosineSimilarity(
      first.embeddings.single,
      second.embeddings.single,
    );
  } finally {
    await task.dispose();
  }
}
```

All eight official formatting modes are supported, including retrieval
documents with titles and query/document roles; omitting `context` passes
none to Google's API. `l2Normalize` and `quantize` (both off by default) go to
Google's postprocessor, and quantized results keep Google's signed-int8 bytes.
The model's 512-token limit includes formatting and special tokens; input is
never truncated or chunked. The model is 183.8 MB and under the
[Gemma Terms](https://ai.google.dev/gemma/terms).

## Proofreader 200M

`TextProofreader` runs Google's pipeline, including tokenization, generation
and the ordered corrections from Google's diff.

```dart
import 'package:mediapipe_text/mediapipe_text.dart';

Future<void> proofread() async {
  final task = await TextProofreader.create(
    TextProofreaderOptions(model: TextModels.proofreader),
  );
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
}
```

Chunks contain newly generated text; the final update carries the complete
corrections, each `same`, `insertion` or `deletion` in native order.

## Summarizer 200M

`TextSummarizer` runs Google's pipeline in either official mode,
`TextSummarizerMode.keypoints` (the default) or `.tldr`, fixed at creation.

```dart
import 'package:mediapipe_text/mediapipe_text.dart';

Future<void> summarize(String article) async {
  final task = await TextSummarizer.create(
    TextSummarizerOptions(
      model: TextModels.summarizer,
      mode: TextSummarizerMode.tldr,
    ),
  );
  try {
    print((await task.summarize(article)).summary);
    await for (final update in task.summarizeStream(article)) {
      if (update.chunk != null) print(update.chunk);
    }
  } finally {
    await task.dispose();
  }
}
```

Google's output is kept as is, bullet markers and whitespace included.

### Streaming, token budgets and cancellation

For Proofreader and Summarizer, streams start on listen and allow one
subscription; pausing buffers updates. Google's API has no cancellation, so
cancelling a stream stops delivery but waits for the native call to finish.
`maxNumTokens` and `cacheDirectory` go to Google's options (null or zero
selects the native default). Budgets include input and output, so an input
that already exceeds the budget returns a native error rather than being
truncated. Both models are 117.6 MB and under the
[Gemma Terms](https://ai.google.dev/gemma/terms).

## Validation

Every task is compared with Google's own Python output for the same model,
runtime and inputs: 26 cases for the classic tasks, 17 for EmbeddingGemma, 9
for Proofreader and 10 for Summarizer. Fresh Flutter apps built from the
packages as pub.dev ships them run the tasks in debug and release, alongside
vision and audio, with one shared engine. From the repository root:

```sh
make get models
make test_text
make example_text
```

`packages/mediapipe-task-text/example_embedding` is the macOS demo of the
modern tasks, with every formatting mode, token-budget preset and streaming.
