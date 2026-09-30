## 0.1.0

First release.

- Audio Classifier on Android, iOS, macOS, Linux, Windows and the web, through
  Google's official runtimes, classifying PCM clips (`AudioData`, with a WAV
  decoder) at any sample rate.
- `AudioClassifierOptions(model: AudioModels.yamnet)` downloads Google's
  pinned YAMNet model on first use; app-supplied paths and bytes still work.
