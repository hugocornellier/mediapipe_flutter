## Unreleased

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
