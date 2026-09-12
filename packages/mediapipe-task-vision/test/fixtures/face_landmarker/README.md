# Official Face Landmarker references

Generated with Google's `mediapipe==1.0.0` macOS arm64 wheel, CPU delegate,
and the unmodified Face Landmarker float16 version 1 bundle (FaceMesh V2).
The JSON records the model, wheel library, source revision, and raw-image hashes.
Photographs and their provenance/license remain in [../face_detection](../face_detection).

Ten IMAGE inputs include five photographs, RGB/RGBA pixels, two faces, a rotated
image, and a blank frame. Two VIDEO sequences cover single-face smoothing,
multi-face tracking, face loss, re-entry, and rotation. All 478 landmarks,
52 blendshape scores, optional fields, face ordering, and 4×4 transforms are
compared, including the C column-major to Python row/column representation.

Native builds can differ numerically from Google's wheel. On the development
Mac, maximum absolute differences across these cases were 0.0000506 for landmark
coordinates, 0.000930 for blendshape scores, and 0.002392 for matrix elements.
Tests allow 0.0001, 0.002, and 0.005 respectively, with exact counts and metadata.
These are numeric tolerances, not changes to preprocessing, models, or graphs.

Regenerate with `tool/generate_face_landmarker_reference.py` in the pinned Python
environment. That script also copies the official drawing connections into Dart.
The tests use checked-in JSON and need no Python installation.
