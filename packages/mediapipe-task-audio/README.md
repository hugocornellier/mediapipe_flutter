# MediaPipe Audio for Flutter

`mediapipe_flutter_audio` runs Google's official MediaPipe **Audio Classifier**
(for example YAMNet's 521 sound categories) from Dart and Flutter. It is part of
the [mediapipe_flutter](../../README.md) fork and is not published to pub.dev.

## Platforms

The task runs on Google's unmodified **MediaPipe 1.0.1** runtime, which
`mediapipe_flutter_core` bundles once and shares with the text tasks and
MagicTouch: **macOS arm64 CPU, macOS 14+**. Other platforms need a separate
1.0.1 integration. Query support before offering the task:

```dart
final support = await queryAudioClassifierCapabilities();
final available = support.supportedDelegates.contains(AudioDelegate.cpu);
```

Every consumer enables the shared runtime in its app pubspec:

```yaml
hooks:
  user_defines:
    mediapipe_flutter_core:
      tasks_runtime: true
```

## Use

```dart
final classifier = await AudioClassifier.create(
  AudioClassifierOptions(modelPath: 'models/yamnet.tflite', maxResults: 3),
);
final clip = decodeWav(await File('clip.wav').readAsBytes());
for (final chunk in await classifier.classify(clip)) {
  print('${chunk.timestampMs} ms: ${chunk.categories.first.name}');
}
await classifier.dispose();
```

`classify` returns one result per chunk the model reads (0.975 s for YAMNet),
each with its start time. It runs on a background isolate; calls are served in
order. `AudioData` takes interleaved samples in -1 to 1 at any sample rate and
channel count; Google's task resamples to the model's rate. `decodeWav` reads
16-bit PCM and 32-bit float WAV files. Options mirror Google's: `maxResults`
(-1 for all) and `scoreThreshold`.

## Validation

`dart run tool/download_model.dart` fetches YAMNet and checks its SHA-256. The
tests compare every chunk of three official MediaPipe sample clips (speech at
16 kHz and 48 kHz, and a clip YAMNet hears as animal and bird sounds) with Google's own Python 1.0.1 output
(`test/fixtures/official_reference.json`): same categories and timestamps,
scores within 0.00001, including resampling from 48 kHz. They also check model
bytes, queued calls, the score threshold, error reporting, disposal and the C
struct layouts against Google's ctypes definitions.
