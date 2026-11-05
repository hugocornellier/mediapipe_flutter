## 0.2.0

- Audio Transcriber: speech to text on Google's 1.2.2 native library, with
  `AudioModels.parakeetTdtV3` (Parakeet TDT 0.6B v3), whole clips or blocks
  ending in `finishStream()`, optional interim results, and segment
  timestamps.
- Text to Speech: `synthesize` and `synthesizeStream` with
  `AudioModels.phonon` (five voices in five locales), speaking rate, voice
  and locale per call, and word timestamps.
- Both run on the CPU on 64-bit Android, iOS, macOS, Linux and Windows, and
  in browsers on `@mediapipe/tasks-audio` 1.2.2, each on a web worker; 32-bit
  Android reports them unavailable.
- Audio Transcriber also offers the GPU delegate where a test saw the GPU do
  the work: macOS, iPhones, and browsers with a hardware WebGPU adapter. Text
  to Speech stays on the CPU, as Google's ignores the delegate (UP-066).
- Google's 1.2.2 native library replaces 1.2.0, and `@mediapipe/tasks-audio`
  1.2.2 replaces 1.2.0-rc.20261018 in browsers.
- Ships Google's `NOTICE` at the package root, beside `LICENSE`.

## 0.1.0

The first release.

- Audio Classifier on Android, iOS, macOS, Linux, Windows and the web,
  through Google's official runtimes, classifying PCM clips (`AudioData`,
  with a WAV decoder) at any sample rate.
- On 32-bit Android (armeabi-v7a) the Audio Classifier runs on the CPU.
- Audio stream mode on every platform: `AudioClassifierOptions(runningMode:
  AudioRunningMode.audioStream)` creates a task that takes blocks of any
  length with `classifyAsync(block, timestampMilliseconds:)` and delivers one
  result per model window on `results`, stamped with where the window's audio
  starts; `dispose()` classifies the tail. Google's own stream runs it on
  Android, iOS, macOS, Linux and Windows; in browsers, where Google has none,
  the package emulates it on Google's clips mode. The rate, channel and
  timestamp checks run in Dart with one message on every platform. Outside
  browsers at most 64 streams can be open at once.
  `classify` on a stream task, and `classifyAsync` or `results` on a clips
  task, throw `StateError`.
- `AudioClassifierResult` has `classifications` (one `Classifications` per
  model head) and `timestampMilliseconds`. `AudioClassifierOptions` extends
  core's `TaskOptions` with Google's classifier settings and `runningMode`.
- `AudioModels.byName` names YAMNet for
  `hooks.user_defines.mediapipe_audio.models`, which
  `dart run mediapipe_core:bundle_models` bundles into the app. `model:` uses
  the bundled copy and downloads at run time only when
  `ModelStore.allowDownloads` is true; app-supplied paths and bytes work too.
