# MediaPipe Audio for Flutter

`mediapipe_flutter_audio` runs Google's official MediaPipe **Audio Classifier**
(for example YAMNet's 521 sound categories) from Dart and Flutter. It is part of
the [mediapipe_flutter](../../README.md) fork and is not published to pub.dev.

## Platforms

The task runs on Google's unmodified runtime, which `mediapipe_flutter_core`
bundles once and shares with the text tasks: **macOS arm64 CPU, macOS 14+**
(MediaPipe 1.0.1), **Linux x64 CPU** (1.0.1) and **Windows x64 CPU** (1.0.0).
On Linux and Windows that runtime is the vision package's wheel library, loaded
once for both packages; Linux needs the system EGL and OpenGL ES libraries
(`libegl1 libgles2` on Debian or Ubuntu) even for CPU. Browsers and Android run
it through
[mediapipe_flutter_audio_web](../mediapipe-task-audio-web/README.md) and
[mediapipe_flutter_audio_android](../mediapipe-task-audio-android/README.md).
Query support before offering the task:

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
16 kHz and 48 kHz, and a clip YAMNet hears as animal and bird sounds) with Google's own Python output
(`test/fixtures/official_reference.json`, from the macOS 1.0.1 wheel): same
categories and timestamps, scores within 0.00001, including resampling from
48 kHz. On Linux and Windows CI, `tool/prepare_audio_reference.py` regenerates
that reference with Google's pinned wheel on the same runner, and
`MEDIAPIPE_AUDIO_REFERENCE_DIR` points the tests at it
(`tool/test_text_audio.py` at the repository root runs both packages this way). They also check model
bytes, queued calls, the score threshold, error reporting, disposal and the C
struct layouts against Google's ctypes definitions.
