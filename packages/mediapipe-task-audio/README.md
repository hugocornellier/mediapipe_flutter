# mediapipe_audio

Google's MediaPipe **Audio Classifier** for Dart and Flutter, for example
YAMNet's 521 sound categories, on Android, iOS, macOS, Linux, Windows and the
web. Google's pinned YAMNet model is bundled with your app at build time:
list it under `hooks.user_defines.mediapipe_audio.models: [yamnet]` in the
app's pubspec, declare `assets/mediapipe/` under `flutter: assets:`, and run
`dart run mediapipe_core:bundle_models` from the app's root.

> **Not on pub.dev yet.** Depend on it by path from a checkout of
> [the repository](https://github.com/hugocornellier/mediapipe_flutter) until
> it is published.

## Platforms

The task runs Google's runtime on each platform, on the CPU: the Android SDK
(`tasks-audio` 1.0.0), an adapter over the 1.0.1 iOS SDK (iOS 15+), the
official wheel libraries on Linux x64 (1.0.1) and Windows x64 (1.0.0),
Google's 1.0.0 library on macOS 14+ arm64, and `@mediapipe/tasks-audio` 1.0.1
in browsers. `mediapipe_core` bundles the native engine once per app, shared
with vision and text.

On macOS the engine is opt-in because it adds about 95 MB:

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

## Use

```dart
import 'dart:io';

import 'package:mediapipe_audio/mediapipe_audio.dart';

Future<void> classifyClip(String wavPath) async {
  final classifier = await AudioClassifier.create(
    AudioClassifierOptions(model: AudioModels.yamnet, maxResults: 3),
  );
  try {
    final clip = decodeWav(await File(wavPath).readAsBytes());
    for (final chunk in await classifier.classify(clip)) {
      print('${chunk.timestampMs} ms: ${chunk.categories.first.name}');
    }
  } finally {
    await classifier.dispose();
  }
}
```

`classify` returns one result per chunk the model reads (0.975 s for YAMNet),
each with its start time. It runs on a background isolate and serves calls in
order. `AudioData` takes interleaved samples in -1 to 1 at any sample rate and
channel count; Google's task resamples to the model's rate. `decodeWav` reads
16-bit PCM and 32-bit float WAV files. Options mirror Google's: `maxResults`
(-1 for all) and `scoreThreshold`. To use your own model, pass `modelPath` or
`modelBytes` instead of `model`.

Samples from a microphone or any other source work the same way: wrap them
in `AudioData`, at whatever rate they were recorded. This sample names the
sound in the latest chunk.

```dart
import 'dart:typed_data';

import 'package:mediapipe_audio/mediapipe_audio.dart';

Future<String?> latestSound(Float32List samples, double sampleRate) async {
  final classifier = await AudioClassifier.create(
    AudioClassifierOptions(model: AudioModels.yamnet, maxResults: 1),
  );
  try {
    final chunks = await classifier.classify(
      AudioData(samples: samples, sampleRate: sampleRate),
    );
    if (chunks.isEmpty || chunks.last.categories.isEmpty) return null;
    return chunks.last.categories.first.name;
  } finally {
    await classifier.dispose();
  }
}
```

Keep one classifier for a live stream and pass it about one second of audio
at a time, YAMNet's window.

Query support before offering the task:

```dart
import 'package:mediapipe_audio/mediapipe_audio.dart';

Future<bool> audioAvailable() async {
  final support = await queryAudioClassifierCapabilities();
  return support.supportedDelegates.contains(AudioDelegate.cpu);
}
```

Failures are `MediaPipeException`s: `RuntimeUnavailableException` (with a
`fix`), `ModelDownloadException`, and `AudioTaskException` for errors from
Google's runtime. `dispose()` drains queued calls and is idempotent.

## Validation

The tests compare every chunk of three official MediaPipe sample clips (speech
at 16 kHz and 48 kHz, and a clip YAMNet hears as animal and bird sounds) with
Google's own Python output (`test/fixtures/official_reference.json`, from the
macOS 1.0.1 wheel; the 1.0.0 engine on macOS matches it): same categories and
timestamps, scores within 0.00001, including resampling from 48 kHz. On Linux
and Windows CI, `tool/prepare_audio_reference.py` regenerates that reference
with Google's pinned wheel on the same runner (`tool/test_text_audio.py` at the
repository root runs both packages this way). The tests also check queued
calls, the score threshold, error reporting, disposal and the C struct layouts
against Google's ctypes definitions. Browser CI compares the Dart API with
Google's JavaScript on the same page and classifies microphone input.
