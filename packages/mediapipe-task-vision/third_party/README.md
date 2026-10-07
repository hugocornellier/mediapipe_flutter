# Native provenance

The vision tasks run on Google's MediaPipe vision library, one of the C
libraries Google builds per task family, here from MediaPipe
`1.1.0-dev.20261005`. This package's build hook bundles it as
`package:mediapipe_vision/mediapipe.dylib` through `mediapipe_core`, which pins
every platform's file by SHA-256 and size
(`mediapipe_core/lib/src/native_assets/family_runtimes.dart`). No MediaPipe
code is compiled or patched here. On macOS, core shortens the library's system
framework paths and signs it again, because Google's build leaves too little
header room for the install names Dart and Flutter write (upstream-issues.md
UP-042); code and data are unchanged.

## Bindings

The Dart bindings are generated with ffigen from MediaPipe's C API headers,
which `mediapipe_core` vendors unchanged from
https://github.com/google-ai-edge/mediapipe/tree/v1.0.0 (commit
`6d31f1ebc3284db74d211d62bdc4f0a0c29ea120`); the 1.1.0 library keeps that ABI.
The Interactive Segmenter's stateful API has no published header, so its
bindings follow Google's Python ctypes definitions. The tests check struct
sizes and field offsets against both.

`FaceLandmarksConnections`, `HandLandmarksConnections` and
`PoseLandmarksConnections` are generated from MediaPipe 1.0.0's official Python
drawing topology, keeping every edge and its order.

## Notices

`LICENSE` and `NOTICE` were copied from Google's official MediaPipe 1.0.0
distribution and cover the larger upstream distribution the vision library is
built from. Google delivers the per-family libraries without license files, so
these stay the package's notices for the bundled library.
`OPENCV_CAROTENE_NOTICES` holds OpenCV 4.12.0's hal/carotene notices, which the
package's former source-built runtime needed; it stays until Google confirms
the notices its own libraries need.

## Reference outputs

The tests compare the bundled library with Google's own Python API for the same
release: the `mediapipe-nightly` 1.1.0rc20260925 wheel for macOS arm64, which
`mediapipe_core`'s `referenceWheels` pins together with its C library. The
wheel is an independent oracle, not the application runtime.
