# Vision API migration

| Before | Now |
| --- | --- |
| Package `mediapipe_flutter_vision`, `import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart'` | Package `mediapipe_vision`, `import 'package:mediapipe_vision/mediapipe_vision.dart'`; build settings move to `hooks.user_defines.mediapipe_vision` |
| `vision_native.dart`, `web.dart`, or task-specific imports | `mediapipe_vision.dart` |
| `modelPath:` or `modelBytes:` only | `model: VisionModels.faceLandmarker` (or one of the existing sources) |
| `VisionRunningMode` | `RunningMode` (`image`, `video`, `liveStream`) |
| Task-specific constructors | `await FaceLandmarker.create(FaceLandmarkerOptions(...))` and the matching `create` method for each task |
| `close()` | `await dispose()` |
| `FaceDetectorException`, `FaceLandmarkerException`, `ObjectDetectorException`, `InteractiveSegmenterException` | `VisionTaskException` (a `MediaPipeException`, with the same `statusCode` and `gpuUnavailable`) |
| `queryLandmarkTaskCapabilities`, `queryImageTaskCapabilities`, `querySegmenterTaskCapabilities` | The per-task query, for example `queryHandLandmarkerCapabilities()` |
| Backend factories and interfaces in application code | Platform plugins import their implementation entrypoints directly. |

Supply exactly one model source. `model:` downloads a verified pinned model on
first task creation. Live stream mode is reserved and currently throws
`UnsupportedError` at creation. Inference futures cannot cancel an in-flight
native call; `Future.timeout` only limits caller waiting. `dispose()` drains
accepted calls and is safe to call again.

Use `queryFaceLandmarkerCapabilities()` and the corresponding
`queryXxxCapabilities()` function for each other task to inspect supported
delegates and the reason an unsupported delegate is unavailable.
