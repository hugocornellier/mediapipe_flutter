# Face Landmarker 1.0.1 compatibility check — 2026-09-14

The runtime upgrade is blocked by an upstream macOS CPU crash. The package
continues using the unmodified 1.0.0 runtime and the latest official model bundle.
No runtime pins, models, bindings, reference outputs or tolerances were changed.

## Model version

Google's [Face Landmarker guide](https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker)
still links to the float16 Face Landmarker bundle containing BlazeFace,
FaceMesh V2 (478 landmarks), and the 52-score blendshape model.
Downloading its `float16/latest/face_landmarker.task` link produced exactly the
same bytes as our pinned `float16/1/face_landmarker.task`:

```text
SHA-256: 64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff
```

MediaPipe 1.0.1 is a runtime release, not a new face model version. Both tested
runtime distributions include the Face Landmarker API.

## CPU comparison

Host: Apple M4 Max, macOS 26.4 (25E246), Python 3.12.7, arm64. Each runtime ran in
its own process with full macOS access, using Google's original Python API and
unmodified macOS arm64 wheel library, the same model, and explicit CPU selection.

| Official runtime | Result |
| --- | --- |
| 1.0.0 | Created and closed successfully; detected a face in each of the four portrait fixtures, twice each, with 478 landmarks, 52 blendshapes and a 4×4 matrix. The group fixture returned no faces with the default single-face setting. |
| 1.0.1 | Process aborted during task creation, before any image was submitted (shell exit status 134 / SIGABRT). |

Original `libmediapipe.dylib` SHA-256 values were checked before initialization:

```text
1.0.0: aa1314b6cc3eb2ce3b610808433930c016e19cdc0f62cbb3f10cc7e912b6f72f
1.0.1: 9cffc37134d98bdbbcc4b5811d2e2acd66361d05b89761e68a5cb72e0406b53a
```

The 1.0.1 crash reported `graph_service.h:139`, `Service is unavailable`,
`DrishtiMetalHelper initWithCalculatorContext:`, and
`mediapipe::api2::TensorsToDetectionsCalculator::Open()`. This matches the open
[upstream regression #6356](https://github.com/google-ai-edge/mediapipe/issues/6356).
It occurs in Google's runtime before Dart bindings or camera input are involved.

To reproduce CPU initialization, install the selected official runtime in an
isolated Python environment and run from the vision package directory:

```python
import mediapipe as mp
from mediapipe.tasks.python import vision

print(mp.__version__, flush=True)
with vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(
    base_options=mp.tasks.BaseOptions(
        model_asset_path="models/face_landmarker.task",
        delegate=mp.tasks.BaseOptions.Delegate.CPU,
    ),
    output_face_blendshapes=True,
    output_facial_transformation_matrixes=True,
)):
    print("created", flush=True)
```

This check blocks replacement of the CPU/GPU runtime; it does not qualify 1.0.1
for GPU release. Exploratory GPU runs initialized Metal but returned empty
results on both wheel versions in the ad hoc probe, so they do not establish
a GPU regression or a passing GPU upgrade. The existing official-reference
GPU suite remains the release criterion after the CPU blocker is resolved.

The retained package runtime passed all 22 selected Face Landmarker tests on
this host (11 CPU and 11 Metal), including official IMAGE/VIDEO references,
padded camera pixels, task coexistence, errors and lifecycle behavior:

```sh
dart test test/face_landmarker_test.dart --name cpu --reporter expanded
dart test test/face_landmarker_test.dart --name gpu --reporter expanded
```

Google's public source tags also stopped at `v1.0.0` when checked. There was no
`v1.0.1` source tag to use for a matching rebuild of our smaller standalone face
library. A future upgrade needs a fixed official runtime, verified source/build
provenance, and the existing CPU/Metal IMAGE/VIDEO and fresh-consumer checks.
