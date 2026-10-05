## 0.2.0

- Audio stream mode on every platform: `AudioClassifierOptions(runningMode:
  AudioRunningMode.audioStream)` creates a task that takes blocks of any
  length with `classifyAsync(block, timestampMilliseconds:)` and delivers one
  result per model window on `results`, stamped with where the window's audio
  starts; `dispose()` classifies the tail. Google's own stream runs it on
  Android, iOS, macOS, Linux and Windows; in browsers, where Google has none,
  the package emulates it on Google's clips mode. The rate, channel and
  timestamp checks run in Dart with one message on every platform. On iOS,
  macOS, Linux and Windows at most 64 streams can be open at once.
- `classify` on a stream task, and `classifyAsync` or `results` on a clips
  task, throw `StateError`.
- The Android plugin builds on core's `TaskHost` for its worker thread,
  model buffers and channel handling, keeping only what Google's audio
  SDK needs; the channel's methods and results are unchanged.
- Breaking: `AudioClassifierResult` is a class with `classifications` (one
  `Classifications` per model head) and `timestampMilliseconds`; the
  `AudioClassifierCategory` record is core's `MediaPipeCategory`. See
  MIGRATION.md.
- Breaking: `AudioClassifierOptions` extends core's `TaskOptions` and adds
  Google's `runningMode` (`AudioRunningMode.audioClips` or `audioStream`),
  `displayNamesLocale`, `categoryAllowlist` and
  `categoryDenylist`. `AudioDelegate` and `AudioTaskException` are core's
  `Delegate` and `TaskException`; `web_runtime.dart` is gone.
- `AudioClassifier` has `delegate` and `runningMode` getters.

- `AudioModels.byName` names YAMNet for
  `hooks.user_defines.mediapipe_audio.models`, which
  `dart run mediapipe_core:bundle_models` bundles into the app.
- Breaking: `model:` uses the app's bundled copy and no longer downloads at
  run time unless `ModelStore.allowDownloads` is true.

## 0.1.0

First release.

- Audio Classifier on Android, iOS, macOS, Linux, Windows and the web, through
  Google's official runtimes, classifying PCM clips (`AudioData`, with a WAV
  decoder) at any sample rate.
- `AudioClassifierOptions(model: AudioModels.yamnet)` downloads Google's
  pinned YAMNet model on first use; app-supplied paths and bytes still work.
- On Android, a task made from model bytes keeps them until it closes, since
  Google's SDK reads them in place (UP-033 in upstream-issues.md).
