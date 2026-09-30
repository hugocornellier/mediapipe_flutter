# Audio API migration

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
