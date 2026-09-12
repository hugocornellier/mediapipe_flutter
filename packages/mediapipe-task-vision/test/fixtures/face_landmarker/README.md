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

`official_gpu_reference.json` is generated independently with the same official
wheel and `--delegate gpu`. The wheel confirms creation of the Metal delegate.
RGB input is expanded to RGBA with opaque alpha before entering the graph because
Apple's GPU image upload does not support three-channel ImageFrames. No model,
graph, coordinates, or reference result is modified to match the Dart wrapper.

On the Apple M4 Max development Mac, maximum absolute differences from the wheel's
GPU results across all stills, tracking sequences and padded input tests were
0.00147671 for coordinates, 0.0290841 for blendshape scores, and 0.0431214 for
matrix elements. GPU tests allow 0.002, 0.04, and 0.06 respectively. Counts,
ordering, optional fields, timestamps, and category names still match exactly.
These measurements describe this fixture suite, not model accuracy in general.
CPU tolerances remain unchanged; CPU and GPU are not expected to be bit-identical.

CI generates the GPU oracle on the same runner as the native task, using the
exact pinned official wheel and the same model/fixtures. All tolerances above
remain unchanged. The physical-Mac goldens remain available for local runs.
See [the GPU comparison guide](../../../tool/GPU_VALIDATION.md).
