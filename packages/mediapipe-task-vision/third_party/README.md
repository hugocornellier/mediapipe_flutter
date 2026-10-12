# Native provenance

The vision tasks run on Google's MediaPipe vision library, one of the C
libraries Google builds per task family, here from MediaPipe
`1.1.1-dev.20261009`. This package's build hook bundles it as
`package:mediapipe_vision/mediapipe.dylib` through `mediapipe_core`, which pins
every platform's file by SHA-256 and size
(`mediapipe_core/lib/src/native_assets/family_runtimes.dart`). No MediaPipe
code is compiled or patched here, and the library is bundled as Google built
it.

## Bindings

The Dart bindings are generated with ffigen from MediaPipe's C API headers,
which `mediapipe_core` vendors unchanged from the same build
(`mediapipe_core/native/README.md`). The Interactive Segmenter's stateful API
has no header in Google's delivery, so its bindings follow Google's Python
ctypes definitions. The tests check struct sizes and field offsets against
both.

`FaceLandmarksConnections`, `HandLandmarksConnections` and
`PoseLandmarksConnections` are generated from MediaPipe 1.0.0's official Python
drawing topology, keeping every edge and its order.

## Notices

`LICENSE` and `NOTICE` were copied from Google's official MediaPipe 1.0.0
distribution and cover the larger upstream distribution the vision library is
built from. Google's October 9, 2026 build ships its own LICENSE and NOTICE
with each family; until the package adopts those, these stay its notices for
the bundled library.
`OPENCV_CAROTENE_NOTICES` holds OpenCV 4.12.0's hal/carotene notices, which the
package's former source-built runtime needed; it stays until Google confirms
the notices its own libraries need.

## Reference outputs

The tests compare the bundled library with Google's own Python API for the
nearest release Google publishes a wheel for (none exists for 1.1.1 yet): the
`mediapipe-nightly` 1.1.0rc20260925 wheel for macOS arm64, which
`mediapipe_core`'s `referenceWheels` pins together with its C library. The
wheel is an independent oracle, not the application runtime.
