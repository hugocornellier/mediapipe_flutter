# Vision API migration

## 0.1.0 to 0.2.0

Every task is now one class with the same API on Android, iOS, macOS, Linux,
Windows and the web. Import only `package:mediapipe_vision/mediapipe_vision.dart`;
it re-exports everything shared from `mediapipe_core`.

| 0.1.0 | 0.2.0 |
| --- | --- |
| `vision_native.dart`, `interface.dart`, `capabilities.dart`, `web_runtime.dart` | `mediapipe_vision.dart` (plugins: `platform_interface.dart`) |
| `detectImage` (Face Detector, Face, Hand, Pose and Holistic Landmarker, Object Detector) | `detect` |
| `recognizeImage`, `classifyImage`, `embedImage`, `segmentImage` | `recognize`, `classify`, `embed`, `segment` |
| `regionOfInterest` and `keypoint` on every web task | `regionOfInterest` on Image Classifier and Image Embedder only, as Google's runtime accepts it |
| `detectBrowserFrame(frame, width:, height:, ...)` | `detectForVideo(VisionImage.fromBrowserFrame(frame, width:, height:), ...)` (and the other `ForVideo` verbs) |
| `attachBrowserOverlay`, `setBrowserOverlayOptions`, `browserOverlayActive` | `BrowserOverlay.attach(task, canvas)`, then `configure(...)`, `active` and `detach()` |
| `BrowserVisionTask`, `SdkVisionTask`, `name`, `maxTimestamp` | Removed; `VisionTask` is the interface every task implements |
| `VisionDelegate` | `Delegate` |
| `VisionTaskException` | `TaskException` |
| `TaskCapabilities<VisionDelegate>` | `TaskCapabilities` |
| `FaceDetection`, `ObjectDetection` | `Detection` |
| `FaceBoundingBox`, `ObjectBoundingBox` | `BoundingBox` |
| `FaceCategory`, `ObjectCategory`, `VisionCategory` | `MediaPipeCategory` |
| `FaceKeypoint` | `NormalizedKeypoint` |
| `FaceLandmark`, `VisionLandmark` | `NormalizedLandmark` (image space), `Landmark` (world landmarks) |
| `FaceTransformationMatrix(values:)` | `Matrix(data:)`; `Matrix.at(row, column)` reads one element |
| `VisionClassifications` | `Classifications` |
| `VisionEmbedding` | `Embedding` |
| `SegmentationResult` | `ImageSegmenterResult` |
| `SegmentationMask` | `ConfidenceMask` |
| `SegmentationStroke`, `SegmentationBrushMode`, `SegmentationPoint` | `Stroke`, `BrushMode`, `NormalizedKeypoint` |
| `GestureClassifierOptions` | `ClassifierOptions` |
| `HandLandmarkConnections`, `PoseLandmarkConnections`, `FaceLandmarkConnections` | `HandLandmarksConnections`, `PoseLandmarksConnections`, `FaceLandmarksConnections` |
| `landmarkTaskCapabilitiesForPlatform`, `imageTaskCapabilitiesForPlatform`, `segmenterTaskCapabilitiesForPlatform` | The task's own `xxxCapabilitiesForPlatform` |
| `ownVisionLists`, `validateLandmarkCount`, `validateVisionConfidence` | Removed from the public API |
| `SegmentationOutputOptions` (web only) | Removed; `ImageSegmenterOptions` holds the outputs |

Behavior that changed:

- The same input checks run on every platform. Video timestamps must be at
  most 9007199254740 ms (the browser limit) everywhere, and the messages
  name the task: "FaceDetector has been disposed."
- `InteractiveSegmenter.setImage` and `segment` report every error through
  the returned `Future`, and creating it with an unavailable delegate throws
  `RuntimeUnavailableException`, as every other task does.

## Before 0.1.0

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
