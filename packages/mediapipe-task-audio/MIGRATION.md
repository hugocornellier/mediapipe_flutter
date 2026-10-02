# Audio API migration

## 0.1.0 to 0.2.0

Import only `package:mediapipe_audio/mediapipe_audio.dart`; it re-exports
everything shared from `mediapipe_core`.

| 0.1.0 | 0.2.0 |
| --- | --- |
| `web_runtime.dart` | `mediapipe_audio.dart` |
| `AudioClassifierResult` record `({timestampMs, categories})` | `AudioClassifierResult` class: `timestampMilliseconds` and `classifications` (one `Classifications` per model head) |
| `chunk.categories` | `chunk.classifications.first.categories` |
| `AudioClassifierCategory` record `({index, score, name})` | `MediaPipeCategory` (`index`, `score`, `categoryName`, `displayName`) |
| `AudioDelegate` | `Delegate`; `AudioClassifierOptions` takes `delegate` |
| `AudioTaskException` | `TaskException` |
| `TaskCapabilities<AudioDelegate>` | `TaskCapabilities` |

`AudioClassifierOptions` extends core's `TaskOptions` and gains Google's
`runningMode` (`AudioRunningMode.audioClips`; `audioStream` is reserved and
refused at `create`), `displayNamesLocale`, `categoryAllowlist` and
`categoryDenylist`. `AudioClassifier` has `delegate` and `runningMode`
getters, and `classify` after `dispose` fails through the returned `Future`.

## Before 0.1.0

| Before | Now |
| --- | --- |
| Package `mediapipe_flutter_audio`, `import 'package:mediapipe_flutter_audio/mediapipe_flutter_audio.dart'` | Package `mediapipe_audio`, `import 'package:mediapipe_audio/mediapipe_audio.dart'`; build settings move to `hooks.user_defines.mediapipe_audio` |
| `modelPath:` or `modelBytes:` only | `model: AudioModels.yamnet` (or one of the existing sources) |
| `AudioClassification` | `AudioClassifierResult` |
| `AudioCategory` | `AudioClassifierCategory` |
| `AudioClassifierException` | `AudioTaskException` (a `MediaPipeException`) |

Import `mediapipe_audio.dart`, then call
`AudioClassifier.create(AudioClassifierOptions(model: AudioModels.yamnet))`.
Supply exactly one model source. `queryAudioClassifierCapabilities()` reports
supported delegates and reasons for unavailable delegates. An in-flight
classification cannot be cancelled; `Future.timeout` limits caller waiting,
and `dispose()` drains accepted calls and is idempotent.
