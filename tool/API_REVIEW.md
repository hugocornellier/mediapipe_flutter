# Public API review

Baseline: Google commit `d3e554e` (2025-06-04). Google's text entrypoint
`mediapipe_text.dart` exported classic classifier, embedder and language detector
tasks and results through one import. Its core entrypoint `mediapipe_core.dart`
exported task options and value containers. The current families add vision,
audio, modern text, model storage and capabilities. This table inventories the
pre-phase symbols reachable from each family's primary library, including
conditional exports. A retained result or value type stays because it carries
the task's output or input without exposing native ownership.

[API_UNIFICATION.md](API_UNIFICATION.md) plans changes to several of these
decisions; its "Superseded decisions" section lists them.

| Package | Current symbol | Google equivalent | Decision and reason |
| --- | --- | --- | --- |
| `mediapipe-core` | `BaseCategory` | `BaseCategory` | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-core` | `BaseClassifications` | `BaseClassifications` | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-core` | `BaseEmbedding` | `BaseEmbedding` | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-core` | `BaseOptions` | `BaseOptions` | Keep for explicit path or byte sources in classic text tasks. |
| `mediapipe-core` | `Category` | `Category` | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-core` | `Classifications` | `Classifications` | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-core` | `ClassifierOptions` | `ClassifierOptions` | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-core` | `ClassifierResult` | `ClassifierResult` | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-core` | `DartAwareChars` | `DartAwareChars` | Hide from primary import; FFI and executor types are implementation details. |
| `mediapipe-core` | `DartAwareFloats` | `DartAwareFloats` | Hide from primary import; FFI and executor types are implementation details. |
| `mediapipe-core` | `DartAwarePointerChars` | `DartAwarePointerChars` | Hide from primary import; FFI and executor types are implementation details. |
| `mediapipe-core` | `DebuggableString` | `DebuggableString` | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-core` | `EmbedderOptions` | `EmbedderOptions` | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-core` | `Embedding` | `Embedding` | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-core` | `EmbeddingType` | `EmbeddingType` | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-core` | `IOTaskResult` | `IOTaskResult` | Hide from primary import; FFI and executor types are implementation details. |
| `mediapipe-core` | `InnerTaskOptions` | `InnerTaskOptions` | Hide from primary import; FFI and executor types are implementation details. |
| `mediapipe-core` | `NativeFloats` | `NativeFloats` | Hide from primary import; FFI and executor types are implementation details. |
| `mediapipe-core` | `NativeInts` | `NativeInts` | Hide from primary import; FFI and executor types are implementation details. |
| `mediapipe-core` | `NativeListOfStrings` | `NativeListOfStrings` | Hide from primary import; FFI and executor types are implementation details. |
| `mediapipe-core` | `NativeStrings` | `NativeStrings` | Hide from primary import; FFI and executor types are implementation details. |
| `mediapipe-core` | `NullAwarePtr` | `NullAwarePtr` | Hide from primary import; FFI and executor types are implementation details. |
| `mediapipe-core` | `TaskExecutor` | `TaskExecutor` | Hide from primary import; FFI and executor types are implementation details. |
| `mediapipe-core` | `TaskOptions` | `TaskOptions` | Hide from primary import; FFI and executor types are implementation details. |
| `mediapipe-core` | `TimestampedClassifierResult` | `TimestampedClassifierResult` | Hide from primary import; FFI and executor types are implementation details. |
| `mediapipe-task-text` | `EmbeddingGemma` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `EmbeddingGemmaException` | none | Remove; merged into `TextTaskException`, which carries the same native `statusCode`. |
| `mediapipe-task-text` | `EmbeddingGemmaOptions` | none | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-task-text` | `EmbeddingTaskType` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `LanguageDetector` | `LanguageDetector` | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `LanguageDetectorExecutor` | `LanguageDetectorExecutor` | Hide; a worker executor is not an application task. |
| `mediapipe-task-text` | `LanguageDetectorOptions` | `LanguageDetectorOptions` | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-task-text` | `LanguageDetectorResult` | `LanguageDetectorResult` | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `LanguagePrediction` | `LanguagePrediction` | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `ProofreadingCorrection` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `ProofreadingCorrectionType` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `TextClassifier` | `TextClassifier` | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `TextClassifierExecutor` | `TextClassifierExecutor` | Hide; a worker executor is not an application task. |
| `mediapipe-task-text` | `TextClassifierOptions` | `TextClassifierOptions` | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-task-text` | `TextClassifierResult` | `TextClassifierResult` | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `TextDelegate` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `TextEmbedder` | `TextEmbedder` | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `TextEmbedderExecutor` | `TextEmbedderExecutor` | Hide; a worker executor is not an application task. |
| `mediapipe-task-text` | `TextEmbedderOptions` | `TextEmbedderOptions` | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-task-text` | `TextEmbedderResult` | `TextEmbedderResult` | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `TextEmbedding` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `TextEmbeddingResult` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `TextFormatContext` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `TextProofreader` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `TextProofreaderException` | none | Remove; merged into `TextTaskException`, which carries the same native `statusCode`. |
| `mediapipe-task-text` | `TextProofreaderOptions` | none | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-task-text` | `TextProofreaderResult` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `TextProofreaderUpdate` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `TextRole` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `TextSummarizer` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `TextSummarizerException` | none | Remove; merged into `TextTaskException`, which carries the same native `statusCode`. |
| `mediapipe-task-text` | `TextSummarizerMode` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `TextSummarizerOptions` | none | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-task-text` | `TextSummarizerResult` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `TextSummarizerUpdate` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `TextTask` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-text` | `TextTaskException` | none | Keep as the one text failure type; `status` renamed `statusCode` to match vision. |
| `mediapipe-task-vision` | `CategoryMask` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `FaceBoundingBox` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `FaceCategory` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `FaceDetection` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `FaceDetector` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `FaceDetectorException` | none | Remove; merged into `VisionTaskException`, which carries the same fields. |
| `mediapipe-task-vision` | `FaceDetectorOptions` | none | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-task-vision` | `FaceDetectorResult` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `FaceKeypoint` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `FaceLandmark` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `FaceLandmarkConnections` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `FaceLandmarker` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `FaceLandmarkerException` | none | Remove; merged into `VisionTaskException`, which carries the same fields. |
| `mediapipe-task-vision` | `FaceLandmarkerOptions` | none | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-task-vision` | `FaceLandmarkerResult` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `FaceTransformationMatrix` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `GestureClassifierOptions` | none | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-task-vision` | `GestureRecognizer` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `GestureRecognizerOptions` | none | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-task-vision` | `GestureRecognizerResult` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `HandLandmarkConnections` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `HandLandmarker` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `HandLandmarkerOptions` | none | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-task-vision` | `HandLandmarkerResult` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `HandTrackingOptions` | none | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-task-vision` | `HolisticLandmarker` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `HolisticLandmarkerOptions` | none | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-task-vision` | `HolisticLandmarkerResult` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `ImageClassifier` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `ImageClassifierOptions` | none | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-task-vision` | `ImageClassifierResult` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `ImageEmbedder` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `ImageEmbedderOptions` | none | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-task-vision` | `ImageEmbedderResult` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `ImageSegmenter` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `ImageSegmenterOptions` | none | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-task-vision` | `InteractiveSegmenter` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `InteractiveSegmenterException` | none | Remove; merged into `VisionTaskException`, which carries the same fields. |
| `mediapipe-task-vision` | `InteractiveSegmenterLegacy` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `InteractiveSegmenterLegacyOptions` | none | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-task-vision` | `InteractiveSegmenterOptions` | none | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-task-vision` | `ObjectBoundingBox` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `ObjectCategory` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `ObjectDetection` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `ObjectDetector` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `ObjectDetectorException` | none | Remove; merged into `VisionTaskException`, which carries the same fields. |
| `mediapipe-task-vision` | `ObjectDetectorOptions` | none | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-task-vision` | `ObjectDetectorResult` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `PoseLandmarkConnections` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `PoseLandmarker` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `PoseLandmarkerOptions` | none | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-task-vision` | `PoseLandmarkerResult` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `SdkVisionTask` | none | Hide; backend seams belong only to platform adapters. |
| `mediapipe-task-vision` | `SegmentationBrushMode` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `SegmentationMask` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `SegmentationOutputOptions` | none | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-task-vision` | `SegmentationPoint` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `SegmentationResult` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `SegmentationStroke` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `VisionCategory` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `VisionClassifications` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `VisionDelegate` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `VisionEmbedding` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `VisionImage` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `VisionLandmark` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `VisionModelOptions` | none | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-task-vision` | `VisionPixelFormat` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `VisionRegionOfInterest` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-vision` | `VisionRunningMode` | none | Rename to `RunningMode`; include live stream without an enum migration. |
| `mediapipe-task-vision` | `VisionTaskException` | none | Keep as the one vision failure type (`statusCode`, `gpuUnavailable`). |
| `mediapipe-task-audio` | `AudioCategory` | none | Rename to `AudioClassifierCategory`; use one result vocabulary per task. |
| `mediapipe-task-audio` | `AudioClassification` | none | Rename to `AudioClassifierResult` and category type; one result type per task. |
| `mediapipe-task-audio` | `AudioClassifier` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-audio` | `AudioClassifierException` | none | Rename `AudioTaskException`, one failure type per family like vision and text. |
| `mediapipe-task-audio` | `AudioClassifierOptions` | none | Keep; add a pinned `model` source and strict source validation. |
| `mediapipe-task-audio` | `AudioData` | none | Keep; task, result, value or capability API remains useful to apps. |
| `mediapipe-task-audio` | `AudioDelegate` | none | Keep; task, result, value or capability API remains useful to apps. |

## Other root-library symbols and phase 3 additions

| Package | Symbol | Google equivalent | Decision and reason |
| --- | --- | --- | --- |
| core | `DownloadAsset` | none | Keep; describes an immutable pinned URL, mirrors and hash. |
| core | `ModelStore` | none | Keep; resolves and verifies pinned model data on demand. |
| core | `ModelDownloadException` | none | Keep; callers can distinguish a failed download from task creation. |
| core | `MediaPipeException` | none | Keep; shared catch point for task and model failures. |
| core | `TaskCreationException` | none | Remove; only audio threw it, while vision and text report the same failure with their family type. |
| core | `InvalidInputException` | none | Remove; nothing threw it. |
| core | `RuntimeUnavailableException` | none | Keep; carries actionable `fix` text. |
| core | `TaskCapabilities` | none | Keep; carries delegates and unavailable reasons. |
| core | `TaskPlatform` | none | Keep; identifies the process target of a capability query. |
| core | `taskPlatformGpuReader` | none | Hide from main; platform adapters set this through the capability library. |
| core | `RuntimeTargets` | none | Keep in capability library; records supported process targets. |
| core | `tasksRuntimeTargets` | none | Keep in capability library; documents core runtime support. |
| core | `macosTasksRuntimeTargets` | none | Keep in capability library; documents the macOS task subset. |
| core | `tasksRuntimeUnavailable` | none | Keep in capability library; provides an opt-in fix string. |
| core | `tasksRuntimeVersionOn` | none | Keep in capability library; reports the pinned runtime version. |
| core | `MediaPipeWebRuntime` | none | Keep in `web_runtime.dart`; browser setup needs one shared URL. |
| vision | `VisionModels` | none | Keep; pins official models in `models.dart`. |
| vision | `RunningMode` | none | Keep; image, video and reserved live stream modes share one type. |
| vision | `BrowserVisionTask` | none | Keep; allows browser frame and overlay handling with a primary import. |
| text | `TextModels` | none | Keep; pins official models in `models.dart`. |
| text | `TextTask` | none | Keep; selects modern text capability details. |
| audio | `AudioModels` | none | Keep; pins YAMNet in `models.dart`. |
| audio | `queryAudioClassifierCapabilities` | none | Keep; task-specific delegate query. |
| audio | `audioClassifierCapabilitiesForPlatform` | none | Keep; pure capability evaluation for a platform snapshot. |

The `queryXxxCapabilities` family uses `TaskCapabilities<Delegate>` throughout.
Each query reports supported delegates and a reason for each unsupported one.
The corresponding `xxxCapabilitiesForPlatform` functions remain available for
testing a platform snapshot; they do not initialize a runtime.

| Package | Task-specific query symbols | Google equivalent | Decision and reason |
| --- | --- | --- | --- |
| vision | `queryFaceDetectorCapabilities`, `queryFaceLandmarkerCapabilities`, `queryObjectDetectorCapabilities` | none | Keep; one query per detector task. |
| vision | `queryHandLandmarkerCapabilities`, `queryPoseLandmarkerCapabilities`, `queryGestureRecognizerCapabilities`, `queryHolisticLandmarkerCapabilities` | none | Keep; one query per landmark task. |
| vision | `queryImageClassifierCapabilities`, `queryImageEmbedderCapabilities`, `queryImageSegmenterCapabilities` | none | Keep; one query per image task. |
| vision | `queryInteractiveSegmenterCapabilities`, `queryInteractiveSegmenterLegacyCapabilities` | none | Keep; their runtime support differs. |
| vision | `queryLandmarkTaskCapabilities`, `queryImageTaskCapabilities`, `querySegmenterTaskCapabilities` | none | Remove; unreleased grouped aliases with no callers, replaced by the per-task queries. |
| text | `queryTextClassifierCapabilities`, `queryTextEmbedderCapabilities`, `queryLanguageDetectorCapabilities` | none | Keep; one query per classic text task. |
| text | `queryEmbeddingGemmaCapabilities`, `queryTextProofreaderCapabilities`, `queryTextSummarizerCapabilities` | none | Keep; one query per modern text task. |
| text | `queryTextTaskCapabilities`, `textTaskCapabilitiesForPlatform` | none | Keep; existing generic modern-text queries remain available. |

Vision also retains the corresponding `xxxCapabilitiesForPlatform` functions for
all the task names above. `TextModels` retains the previous `*Model` constants in
`models.dart` as aliases; the primary import exposes only the namespace. Audio
retains `yamnetModel` in `models.dart` for the same reason. Backend factories,
backend interfaces, FFI bindings and direct platform registration entrypoints
are outside the main imports. Plugin authors use `platform_interface.dart`.

## Additional public entrypoints

`platform_interface.dart` is reserved for plugin registration. Legacy `io.dart`,
`interface.dart`, `web.dart`, `vision_native.dart`, `*_backend.dart`, and direct
`*_android.dart` / `*_web.dart` imports are implementation or migration entrypoints;
application examples use the primary library only.
