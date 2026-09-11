# MediaPipe GenAI for Flutter

`mediapipe_flutter_genai` is the legacy LLM wrapper in the private
[mediapipe_flutter](../../README.md) fork. It is not published to pub.dev.

Build tooling and dependencies have been updated for Flutter 3.44.8 stable /
Dart 3.12.2. The native hook downloads pinned, checksum-verified 2024 binaries.
No experimental flags are required.

**LLM inference remains unvalidated.** The example's tests cover Dart state only.
The API below is historical; it does not implement current Summarizer, Proofreader,
or `.litertlm` support. Recovery of this backend is separate from the text baseline.

Runtime artifacts exist for macOS arm64, Android arm64, and iOS arm64 devices.
There are no simulator, Intel macOS, Windows, Linux, or web artifacts for this
package. Use the local path dependencies in `example/pubspec.yaml`.

## Inherited API examples

The following describes the old model and engine API, pending runtime recovery.

### Add tflite models

Unlike other MediaPipe task flavors (text, vision, and audio), generative AI
models must be downloaded at runtime from a URL hosted by the developer. To
acquire these models, you must create a [Kaggle](https://www.kaggle.com/) account,
accept the Terms of Service, download whichever models you want to use in your
app, self-host those models at a location of your choosing, and then configure
your app to download them at runtime.

See the example directory for the inherited implementation; it has not been
validated for native LLM inference on the current baseline.

### CPU vs GPU models

Inference tasks can either run on the CPU or GPU, and each model is compiled once
for each strategy. When you choose which model(s) to use from Kaggle, note their
CPU vs GPU variants and be sure to invoke the appropriate options constructor.

### Initialize your engine

Inference example:

```dart
import 'package:mediapipe_flutter_genai/mediapipe_flutter_genai.dart';

// Location where you downloaded the file at runtime, or
// placed the model yourself in advance (using `adb push`
// or similar)
final String modelPath = getModelPath();

// Select the CPU or GPU runtime, based on your model
// See the example for suitable values to pass to the rest
// of the `LlmInferenceOptions` class's parameters.
bool isGpu = yourValueHere;
final options = switch (isGpu) {
  true => LlmInferenceOptions.gpu(
    modelPath: modelPath,
    ...
  ),
  false => LlmInferenceOptions.cpu(
    modelPath: modelPath,
    ...
  ),
};

// Create an inference engine
final engine = LlmInferenceEngine(options);

// Stream results from the engine
final Stream<String> responseStream = engine.generateResponse('Hello, world!');
await for (final String responseChunk in responseStream) {
  print('the LLM said: $chunk');
}
```

## Issues and feedback

Please file mediapipe_flutter specific issues, bugs, or feature requests in our [issue tracker](https://github.com/hugocornellier/mediapipe_flutter/issues/new).

Issues that are specific to Flutter can be filed in the [Flutter issue tracker](https://github.com/flutter/flutter/issues/new).

To contribute a change to this plugin,
please review our [contribution guide](https://github.com/hugocornellier/mediapipe_flutter/blob/main/CONTRIBUTING.md)
and open a [pull request](https://github.com/hugocornellier/mediapipe_flutter/pulls).
