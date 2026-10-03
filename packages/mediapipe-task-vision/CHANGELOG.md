## 0.2.0

- `RunningMode.liveStream` no longer throws: every camera-capable task
  creates in live stream mode on every platform, the web included, with
  `detectAsync` (`recognizeAsync`, `classifyAsync`, `embedAsync`,
  `segmentAsync`), a `results` stream and `droppedFrames`. Google's flow
  limiter (one frame in flight, the newest one waiting) runs in front of
  Google's VIDEO graph, so a frame that runs gets the result Google's
  LIVE_STREAM gives it, and a dropped frame is never copied to the runtime.
  `VisionImage.deferred` lets a live stream frame be converted only when the
  task starts it, so a dropped frame costs no conversion either.
- The Android plugin builds on core's `TaskHost` for its worker thread,
  model buffers and channel handling, keeping only what Google's vision
  SDK needs; the channel's methods and results are unchanged.
- Breaking: every task is one class with the same API on Android, iOS,
  macOS, Linux, Windows and the web, and `mediapipe_vision.dart` is the only
  app library. `interface.dart`, `vision_native.dart`, `capabilities.dart` and
  `web_runtime.dart` are gone. See MIGRATION.md.
- Breaking: Google's verbs: `detect`, `recognize`, `classify`, `embed` and
  `segment` replace `detectImage`, `recognizeImage`, `classifyImage`,
  `embedImage` and `segmentImage`; the `ForVideo` methods keep their names.
  Only Image Classifier and Image Embedder take a region of interest.
- Breaking: results use core's shared types (`Detection`, `BoundingBox`,
  `MediaPipeCategory`, `NormalizedLandmark` and `Landmark`, `Matrix`,
  `Classifications`, `Embedding`, `ConfidenceMask`); `SegmentationResult` is
  `ImageSegmenterResult`, and `VisionDelegate` and `VisionTaskException` are
  core's `Delegate` and `TaskException`.
- Breaking: `VisionImage.fromBrowserFrame` and `BrowserOverlay` replace the
  web-only `detectBrowserFrame` and overlay methods, and exist everywhere.
- Breaking: the Interactive Segmenter takes Google's `Stroke` and `BrushMode`
  and returns a `ConfidenceMask`. `Hand`, `Pose` and
  `FaceLandmarksConnections` take Google's names; `ClassifierOptions`
  replaces `GestureClassifierOptions`; the grouped capability helpers are
  gone.
- The same input checks run on every platform, with the browser's timestamp
  limit (9007199254740 ms) everywhere; errors name the task.
- Android and browser results go through one decoder; Android boxes keep
  their whole-pixel edges.

- Breaking: `InteractiveSegmenterLegacy`, its options, its model
  (`VisionModels.interactiveSegmenterLegacy`) and its capability query are
  gone. The stateful `InteractiveSegmenter` is the one Interactive Segmenter;
  Google's Android task never served the legacy API (UP-020).
- `VisionModels.byName` names every pinned model for
  `hooks.user_defines.mediapipe_vision.models`, which
  `dart run mediapipe_core:bundle_models` bundles into the app.
- Breaking: `model:` uses the app's bundled copy and no longer downloads at
  run time unless `ModelStore.allowDownloads` is true.
- macOS GPU tasks keep working when the app deletes the model file after
  creating them. The reopen that bounds their memory (UP-032) read the file
  again and failed with `Unable to open file`, about 30 seconds into a
  640x480 camera stream; tasks that can reopen now hold the model in memory.

## 0.1.0

First release.

- Face Detector, Face Landmarker, Hand Landmarker, Gesture Recognizer, Pose
  Landmarker, Holistic Landmarker, Object Detector, Image Classifier, Image
  Embedder, Image Segmenter and Interactive Segmenter on Android, iOS, macOS,
  Linux, Windows and the web, through Google's official runtimes.
- `XxxOptions(model: VisionModels.faceLandmarker)` downloads Google's pinned
  model on first use; app-supplied paths and bytes still work.
- Image and video running modes; `queryXxxCapabilities()` reports supported
  delegates and why others are unavailable.
- The `tasks` build setting bundles only the native runtimes an app uses.
- On macOS, a GPU task reopens its native task after converting 1 GiB of
  frames, since Google's macOS GPU path keeps every frame until the task
  closes (UP-032 in upstream-issues.md).
