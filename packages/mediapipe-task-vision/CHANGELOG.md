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
