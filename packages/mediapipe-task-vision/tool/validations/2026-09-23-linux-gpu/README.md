# Linux GPU face tasks, 2026-09-23

Face Detector and Face Landmarker on Linux x64 with `VisionDelegate.gpu`, using
Google's official `mediapipe==1.0.1` wheel runtime (library
`b72e6d61a79d1080d29a96ba95e3cfa3e43f6c433c0acc3bc9b3eb7ac0ba103a`), unmodified.
Why 1.0.1 and how the renamed renderer came about:
[the desktop GPU note](../2026-09-23-desktop-gpu/).

Run [35831482489](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/35831482489),
job "Vision face tasks / ubuntu-24.04 x64 GPU", on `ubuntu-24.04` with Mesa
25.2.8's llvmpipe, `EGL_PLATFORM=surfaceless`, and `force_gl_renderer` set so
Google's software-renderer check passes. This verifies results; it says nothing
about speed on a real GPU.

## Results

- Google's Python API generated same-host GPU references for both tasks
  (`reference/`). Every generator log shows an OpenGL ES 3.2 context on the
  renamed renderer (`face_detector.log`, `face_landmarker.log`), recorded in
  the receipt as `gl_confirmed`.
- The Dart GPU suites then passed against those references with unchanged
  tolerances: 70 tests, 1 skipped (the refusal test, run separately;
  `dart-tests.log`). The measured difference between the Dart tasks and
  Google's same-host output was 0.0 for every box, score, keypoint, landmark,
  blendshape and matrix value.
- Against the checked-in GPU references from a physical Mac (Metal), this
  runner's official GPU output differs by at most 0.0023 in landmarks, 0.046 in
  blendshape scores, 0.038 in transform values, 0.0004 in scores and one pixel
  in boxes (`reference/provenance.json`). Those are differences between GPUs,
  not the wrapper, which is why the Linux GPU suites only accept same-host
  references.
- Without the rename, Google refused the llvmpipe context and `create()` failed
  with `FaceLandmarkerException.gpuUnavailable` and a `kGpuService` message;
  nothing retried on CPU (`refusal.log`).
- The same run's Linux CPU job passed all eleven tasks on 1.0.1 against
  same-host official CPU references.

## Not established

- A physical GPU, and GPU speed. Run [`../../test_linux_gpu.sh`](../../test_linux_gpu.sh)
  on one.
- Object Detector and the other tasks on the Linux GPU.

`sha256.json` covers the files here.
