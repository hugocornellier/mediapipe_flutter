# mediapipe_decision

Google's MediaPipe Decision Maker for Dart and Flutter. Ask a yes-or-no,
choice or score question about a piece of text and get Google's answer with
calibrated probabilities, in one forward pass of a small model rather than by
generating text. Every call runs Google's official MediaPipe pipeline.

> **Not on pub.dev yet.** Depend on it by path from a checkout of
> [the repository](https://github.com/hugocornellier/mediapipe_flutter) until
> it is published.

## Platforms

| Task | Class | Android | iOS | macOS arm64 | Linux x64 | Windows x64 | Web |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Decision Maker | `DecisionMaker` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

The runtimes are Google's MediaPipe 1.1.0: its per-family decision C
library, which this package's build hook downloads and checks against its
SHA-256 on Android 9+, iOS 15+, macOS 14+ and Linux, on the CPU; the C
library from Google's official Python wheel on Windows, which that delivery
lacks, downloaded from PyPI and checked the same way; and
`@mediapipe/tasks-decision` 1.1.0 in browsers, on the GPU delegate. Google's
browser runtime fails every evaluation on the CPU delegate and on browsers
without a hardware WebGPU adapter
([UP-049](../../upstream-issues.md#up-049-the-browser-decision-maker-fails-every-evaluation-without-a-hardware-webgpu-adapter)),
so `queryDecisionMakerCapabilities()` offers browsers only the GPU, and only
on such an adapter; there it answers as the desktop library does.

Google's per-family decision library (its delivery of October 8, 2026)
covers every target but Windows, so Windows alone bundles the library from
Google's wheel (`wheelRuntimes` in mediapipe_core) until Google builds one;
the bindings are the same, since both libraries export the same C API. The
per-family library fails every evaluation with the text-only EmbeddingGemma
2 model, which the wheel's library and Google's browser runtime run
([UP-053](../../upstream-issues.md#up-053-the-per-family-decision-library-fails-every-evaluation-with-the-text-only-embeddinggemma-2-model)):
`queryDecisionMakerCapabilities(model)` says where a model runs, `create`
refuses one the runtime here cannot before downloading it, and
`DecisionModels.embeddingGemma2TextVision` answers the same on every
runtime.

## Quick start

```dart
import 'package:mediapipe_decision/mediapipe_decision.dart';

Future<void> decide() async {
  final capabilities = await queryDecisionMakerCapabilities();
  final task = await DecisionMaker.create(
    DecisionMakerOptions(
      model: DecisionModels.layaS256,
      // The CPU natively, the GPU in browsers.
      delegate: capabilities.supportedDelegates.first,
    ),
  );
  try {
    const text = 'My order arrived broken and I want my money back.';
    final refund = await task.evaluateBoolean(
      text,
      BooleanQuestion('The customer wants a refund.'),
    );
    final topic = await task.evaluateChoice(
      text,
      ChoiceQuestion({
        'shipping': 'A problem with delivery or a damaged package',
        'billing': 'A question about a charge or a refund',
        'other': 'Anything else',
      }),
    );
    final mood = await task.evaluateScore(
      text,
      ScoreQuestion(['very unhappy', 'unhappy', 'neutral', 'happy']),
    );
    print('${refund.value} ${topic.selectedKey} ${mood.expectedScore}');
  } finally {
    await task.dispose();
  }
}
```

`DecisionModels` pins Google's decision models: Laya and GLiNER2.5-Decide
(`layaS256`, `layaS512`, `glinerS256`, `glinerS512`: 678 MB to 1.08 GB),
and EmbeddingGemma 2, which answers as fast at a fraction of the download:
`embeddingGemma2Text` (165 MB) on Windows and in browsers, and
`embeddingGemma2TextVision` (388 MB) everywhere (UP-053 above). They are
large, so an app usually downloads one on first use rather than bundling
it: set
`ModelStore.allowDownloads = true` before `create`, or pass `modelPath`.
In browsers, `modelPath` can be the model's URL in Google's bucket, which
Google's runtime then fetches itself.

## Questions and answers

- `BooleanQuestion(condition, threshold:, temperature:, normalizePrior:)`
  answers with `BooleanResult(value, probabilityTrue, confidence)`.
- `ChoiceQuestion(criteria, instructions:, temperature:, scoringMode:,
  normalizePrior:)`, where `criteria` maps each option's key to a
  description, answers with `ChoiceResult(selectedKey, probabilities,
  confidence, predictionSet)`. The probabilities come in the question's
  order on every platform, and the prediction set is Google's Python rule:
  the most likely keys until 90% is covered.
- `ScoreQuestion(rubric, instructions:, temperature:)`, lowest level first,
  answers with `ScoreResult(expectedScore, probabilities, confidence,
  selectedKey)`.

Each has a batch form (`evaluateBooleanBatch` and so on) with an optional
`sharedPrefix`. Calls run one at a time, in call order.
