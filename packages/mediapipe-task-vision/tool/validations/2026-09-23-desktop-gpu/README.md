# Desktop GPU validation, 2026-09-23

Can Face Landmarker use a GPU on Linux or Windows desktops? Hosted runners
have no GPU, only software renderers: Mesa's llvmpipe (OpenGL ES) on
`ubuntu-24.04` and WARP (Direct3D 12) on `windows-2025`. These runs show
whether a GPU path works, not how fast it is. Nothing shipped changes: the
Linux and Windows packages keep Google's official CPU runtime.

| | Linux x64 | Windows x64 |
| --- | --- | --- |
| Official 1.0.0 | GPU compiled out | GPU compiled out |
| Official 1.0.1 | Built with GPU; refuses software renderers; untested on a physical GPU | GPU compiled out |
| Unmodified upstream v1.0.0 built with GPU | **Works** on llvmpipe | Not possible: upstream disables GPU on Windows |

## Official runtime

[`desktop-gpu-probe.yaml`](../../../../../.github/workflows/desktop-gpu-probe.yaml)
installs the PyPI wheel and runs Face Landmarker in IMAGE mode on the CPU,
then the GPU delegate, over the licensed `landmark-ex1.jpg` portrait. Runs
[35794681057](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/35794681057) (1.0.0),
[35794967149](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/35794967149) (1.0.1 before Mesa's EGL was installed) and
[35796245827](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/35796245827) (1.0.1).

- 1.0.0 on both systems, and 1.0.1 on Windows: graph validation fails with
  `ImageCloneCalculator: GPU processing is disabled in build flags`. Google's
  WebGPU accelerator plug-in from `ai-edge-litert` 2.1.6 and 2.2.0 changes
  nothing, since the graph is rejected before inference.
- 1.0.1 on Linux is built with GPU. Its library links `libEGL.so.1` and
  `libGLESv2.so.2` and does not load without them, even for CPU
  (`official/1.0.1-linux-cpu-without-libegl.log`). With Mesa's EGL it created an
  OpenGL ES 3.2 llvmpipe context, then refused it:
  `GPU emulation detected, but not supported. Please run in an environment that exposes a physical GPU.`
  In the wheel's `libmediapipe.so`, `mediapipe::GlContext::FinishInitialization`
  returns `kInternal` whenever `GL_RENDERER` contains `llvmpipe` or `softpipe`,
  reporting `third_party/mediapipe/gpu/gl_context.cc:419` from Google's internal
  tree; no flag or environment variable is consulted. Public source has no such
  check (tag `v1.0.0`; branches `master`, `release`, `1.0.0` and `staging`,
  checked 2026-09-22), so only a physical GPU can exercise 1.0.1's GPU path.
- CPU landmarks from 1.0.0 and 1.0.1 are bit-identical on Linux and on Windows,
  and across the two (`report.json`, `cpu_landmarks_sha256`).

## Unmodified upstream source built with GPU, Linux

[`linux-gpu-build.yaml`](../../../../../.github/workflows/linux-gpu-build.yaml)
builds `//mediapipe/tasks/c:libmediapipe.so` from pinned, unmodified upstream
`6d31f1eb` (v1.0.0, the macOS runtime's revision) with the GPU options Google's
`setup.py` applies when `MEDIAPIPE_DISABLE_GPU=0`, plus `--define=OPENCV=source`,
using Bazel 7.4.1. Run
[35803134048](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/35803134048);
the first, uncached build took 44 minutes in
[35795326661](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/35795326661).

| | CPU | GPU, `EGL_PLATFORM=surfaceless` |
| --- | --- | --- |
| C API smoke | 478 landmarks, 52 blendshapes, 4×4 matrix | 478 landmarks, 52 blendshapes, 4×4 matrix |
| Python API, median of 30 images | 9.74 ms | 114.90 ms |
| Task creation, first image | 40 ms, 20 ms | 489 ms, 624 ms |

- Renderer: `OpenGL ES 3.2 Mesa 25.2.8-0ubuntu0.24.04.2`, `llvmpipe (LLVM 20.1.2, 256 bits)`.
  With the default EGL platform the display-less runner fails with
  `Unable to initialize EGL` (`source-build/smoke-gpu-default.log`).
- GPU against CPU on the portrait: largest per-coordinate difference 0.0124
  (x, y and z); x,y distance mean 0.0036, maximum 0.0129. Google's own GPU paths
  differ as much on the same image and measure: 0.0131 with Metal on iOS
  ([2026-09-17](../2026-09-17-ios-official-gpu/)) and 0.0132 on Android
  ([2026-09-18](../2026-09-18-android-face-sdk/)). This build's CPU output
  matches Google's official CPU within 0.00003.
- The GPU ran the inference. Tasks set `use_advanced_gpu_api`, so upstream
  selects `InferenceCalculatorGlAdvanced`: it runs the detector and landmark
  models through TensorFlow Lite's GPU backend directly (OpenCL is compiled only
  for Android and ChromeOS, so here OpenGL), never through the interpreter's
  delegate API, so TensorFlow Lite's `Created ... delegate for GPU` line cannot
  appear. The interpreter runner's `Feedback manager` warning appears twice on
  CPU and never on GPU, and `tensor.cc` logged once from an OpenGL buffer write
  (`Tensors are designed for single writes`, upstream's once-only warning, with
  no visible effect). The XNNPACK line in the GPU logs is the blendshape model,
  which Google's graph keeps on CPU.
- Upstream's default links OpenCV 3.4 as eight shared `libopencv_*.so.3.4`
  libraries: 53.7 MB beside a 23.3 MB `libmediapipe.so` (sizes and SHA-256 in
  `report.json`). Google's 1.0.1 wheel links OpenCV 4.13.0 statically.

## Windows

Upstream v1.0.0's `mediapipe/gpu/BUILD` makes `disable_gpu` true on
`@platforms//os:windows` ("Also disable GPU on Windows since it's not supported
(use pthread).") and marks the GPU library incompatible with Windows, so no
build flag enables it. A Windows GPU path needs upstream changes (for example
ANGLE for OpenGL ES, and replacing the pthread code), or a separate pipeline
running the models through LiteRT with its WebGPU accelerator and our own pre-
and post-processing.

## Not established

- Any physical GPU, for official 1.0.1 or for this build.
- Speed: llvmpipe emulates the GPU on the CPU.
- A shippable Linux GPU runtime: it would need OpenCV linked statically, as in
  Google's wheel, and the provenance and fresh-consumer checks the macOS source
  runtime has.

Both workflows are manual:
`gh workflow run desktop-gpu-probe.yaml -f mediapipe_version=1.0.1` and
`gh workflow run linux-gpu-build.yaml`. The runs above used them from the
`probe/desktop-gpu` branch; the committed versions differ from the final runs'
only in triggers, the manual version default and comments. `sha256.json`
covers the evidence files here.
