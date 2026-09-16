# Object Detector

The official EfficientDet-Lite0 detector, served by the combined source-built
runtime (`//mediapipe/tasks/c:libmediapipe`). Float32 rather than int8 because
Metal needs a float model.

Models are pinned in `lib/models.dart` and fetched by
`dart tool/download_object_detector.dart`. Goldens come from Google's official
Python API at mediapipe 1.0.0, the same revision the runtime is built from, via
`tool/generate_object_detector_reference.py`. 1.0.1 is deliberately not used:
every graph with a `TensorsToDetectionsCalculator` aborts on CPU there (upstream
#6356), and this is one.

## Metal is validated; CPU is not

Metal reproduces the official Python GPU reference exactly, box for box and
score for score, across all nine image cases and the video sequence.

**CPU inference aborts with `SIGILL`** in this build. The faulting frame is
XNNPACK's KleidiAI SME kernel:

```
si_signo=Illegal instruction: 4, si_code=ILL_ILLTRP(2)
kai_run_lhs_pack_f32p2vlx1_f32_sme+0x20
xnn_compute_inline_packed_qp8gemm+0x164
...
mediapipe::api2::InferenceCalculatorCpuImpl::Process
```

Observed on an M4 Max, which reports SME support. The CPU group in
`test/object_detector_test.dart` is skipped for this reason, not because the
path is untested.

### What this is not

- **Not a wrapper defect.** `tool/object_detector_probe.cc` reproduces the crash
  with no Dart in the process:
  ```sh
  xcrun clang++ -std=c++17 -I <mediapipe-v1.0.0-source> \
    tool/object_detector_probe.cc build/native/tasks/libmediapipe.dylib -o /tmp/od_probe
  # The genrule renames the file but not its install name, so dyld still wants
  # libmediapipe_source.dylib.
  mkdir -p /tmp/odlib && cp build/native/tasks/libmediapipe.dylib /tmp/odlib/libmediapipe_source.dylib
  DYLD_LIBRARY_PATH=/tmp/odlib /tmp/od_probe models/efficientdet_lite0.tflite \
    test/fixtures/face_detection/landmark-ex1.jpg cpu   # exits 132 (128+SIGILL)
  ```
  The same probe with `gpu` exits 0 and prints the reference detections.
- **Not the model or the images.** Google's official 1.0.0 wheel runs the same
  model over the same fixtures on CPU without crashing; that run is what
  produced `official_reference.json`.
- **Not a MediaPipe 1.0.1 issue.** This is the pinned v1.0.0 source build.

### Why the face tasks are unaffected

BlazeFace and the Face Landmarker do not reach XNNPACK's `qp8gemm` path, so
their CPU builds never enter these kernels.

### Not yet ruled out

The difference is in how the KleidiAI kernels are built, not in whether they are
present: Google's wheel exports the same `kai_run_lhs_pack_f32p2vlx1_f32_sme`
symbol and runs on the same CPU. XNNPACK selects these kernels at runtime from
`cpuinfo_has_arm_sme()`, so this cannot be turned off by hardware detection.

It also cannot currently be turned off by build flag. In this XNNPACK revision
the `kleidiai_enabled`, `arm_sme_enabled` and `arm_sme2_enabled` aliases in
`BUILD.bazel` resolve every branch, including `..._explicit_false`, to
`..._explicit_true`, so `--define=xnn_enable_kleidiai=false` and
`--define=xnn_enable_arm_sme=false` are no-ops.

Worth trying next: pinning a different XNNPACK/KleidiAI revision, patching those
aliases in a local override, or comparing the exact `-march`/target-feature
flags the wheel's KleidiAI objects were compiled with against ours.
