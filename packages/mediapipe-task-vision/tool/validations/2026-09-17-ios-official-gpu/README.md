# Official iOS SDK CPU/Metal validation — 2026-09-17

Device: iPhone 15 Pro, Apple A17 Pro, iOS 26.5. Release builds use Google's
prebuilt MediaPipe Tasks 1.0.1 SDK through the Objective-C++ FFI adapter. See
[`IOS_OFFICIAL_SDK.md`](../../IOS_OFFICIAL_SDK.md) for pinned downloads and
reproduction commands.

- `sdk-smoke.json`: both CPU and GPU passed IMAGE and VIDEO execution using
  the public Dart worker-isolate API. The portrait produced 478 landmarks,
  52 blendshapes and one 4×4 facial transformation. File input, padded
  RGB/RGBA/BGRA buffers, all quarter-turn rotations, blank input, strict video
  timestamps, repeated disposal, detector/landmarker coexistence and recovery
  after invalid model creation passed. Face Detector returned six keypoints.
- `camera-smoke.json`: one gallery `LiveCameraController` switched CPU → GPU
  → CPU and processed 21 front-camera BGRA frames per selection at 480×640.
  The captured scene contained no detected face. This verifies capture,
  timestamps and delegate lifecycle; face-bearing inference is exercised by
  the portrait test above. These short runs are not speed benchmarks.
- The device console explicitly reported
  `INFO: Created TensorFlow Lite delegate for Metal.` for GPU initialization;
  CPU initialized the XNNPACK delegate. Google's graph keeps blendshape
  inference on XNNPACK for either selection.
- All 177 face/native-assets tests and all 13 camera geometry tests passed.
  Static analysis of vision library/hook and gallery/validation entrypoints
  reported no issues.

The portrait CPU/GPU maximum landmark difference was approximately 0.0131.
This is recorded as an observation, not compared to macOS accuracy tolerances.
Rotated raster comparisons allow differences from crop/pixel-center sampling;
the actual deltas are in the report. UIKit-versus-Flutter JPEG differences are
also recorded separately, while identical pixel buffers in each channel format
must agree within 0.001. No existing accuracy tolerances were changed.

The device SDK itself was first exercised in an independent Objective-C app
before integrating it into Flutter; both CPU and Metal returned 478 landmarks,
52 blendshapes and a transform on thirteen portrait video frames. The Flutter
integration then exercised the same public SDK through the existing Dart API.
