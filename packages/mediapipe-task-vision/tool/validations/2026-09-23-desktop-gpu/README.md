# Desktop GPU validation, 2026-09-23

Can Face Landmarker use a GPU on Linux or Windows desktops? Hosted runners
have no GPU, only software renderers: Mesa's llvmpipe (OpenGL ES) on
`ubuntu-24.04` and WARP (Direct3D 12) on `windows-2025`. These runs show
whether a GPU path works, not how fast it is. Nothing shipped changes: the
Linux and Windows packages keep Google's official CPU runtime.

| | Linux x64 | Windows x64 |
| --- | --- | --- |
| Official 1.0.0 | GPU compiled out | GPU compiled out |
| Official 1.0.1 | Built with GPU; refuses software renderers by name; **works** on llvmpipe with the renderer renamed; untested on a physical GPU | GPU compiled out |
| Unmodified upstream v1.0.0 built with GPU | **Works** on llvmpipe | Not possible: upstream disables GPU on Windows |
| LiteRT WebGPU accelerator, Face Landmarker's models outside MediaPipe | Not tested | Detector and landmarks **work** on WARP; blendshapes fail |

## Official runtime

[`desktop-gpu-probe.yaml`](../../../../../.github/workflows/desktop-gpu-probe.yaml)
installs the PyPI wheel and runs Face Landmarker in IMAGE mode on the CPU,
then the GPU delegate, over the licensed `landmark-ex1.jpg` portrait. Runs
[35794681057](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/35794681057) (1.0.0),
[35794967149](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/35794967149) (1.0.1 before Mesa's EGL was installed) and
[35796245827](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/35796245827) (1.0.1) and
[35827886063](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/35827886063) (1.0.1, renderer renamed).

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
  checked 2026-09-22), and upstream has no `v1.0.1` tag.
- Renaming the renderer gets past that check without changing Google's library
  or Mesa's rendering. Mesa's `force_gl_renderer` option, set as an environment
  variable, replaces only the reported `GL_RENDERER` string; here it was
  `Mesa software rasterizer, renamed for a MediaPipe CI test`. 1.0.1 then ran
  Face Landmarker on the GPU (`official/1.0.1-linux-gpu-renamed.log`): 1 face,
  478 landmarks, task creation 1.6 s, first image 15.1 s, then a 139 ms median
  (llvmpipe emulation; CPU about 10 ms).
- Its GPU landmarks (`official/1.0.1-linux-gpu-renamed.json`) differ from the
  same run's CPU landmarks (`official/1.0.1-linux-cpu.json`) by at most 0.0121
  per coordinate, and from the source build's GPU landmarks below by at most
  0.0002. This shows 1.0.1's GPU results are correct on this renderer; it does
  not mean Google supports software GPUs.
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

### LiteRT's GPU accelerator

[`windows-gpu-litert-probe.yaml`](../../../../../.github/workflows/windows-gpu-litert-probe.yaml)
asks whether a pipeline outside MediaPipe could use a Windows GPU. It runs the
three models inside Face Landmarker's official bundle through LiteRT's
`CompiledModel` with the WebGPU accelerator from `ai-edge-litert` 2.1.5 (the
version `flutter_litert` ships) and 2.2.0, on WARP (`Microsoft Basic Render
Driver`, Direct3D 12), and compares each output with LiteRT's CPU path on the
same portrait (`windows-litert/`).

- Dawn, the accelerator's WebGPU engine, needs Microsoft's DirectX Shader
  Compiler, which Windows does not include. Without `dxcompiler.dll` and
  `dxil.dll` next to the executable, GPU model creation fails
  (`DynamicLib.Open: dxil.dll Windows Error: 87`, run
  [35825917288](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/35825917288),
  `windows-litert/2.2.0-without-dxc/`).
- With the official DXC release's DLLs (run
  [35826556894](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/35826556894)),
  both versions ran the detector and landmark models fully on the GPU. At the
  default half precision, landmarks differ from CPU by at most 0.0045
  (normalized x,y), and the detector picks the same anchor with a box within
  0.03 input pixels. At 32-bit precision landmarks match CPU exactly, and every
  raw output is within 0.00015.
- The blendshape model fails on GPU: 59 of its 182 operations (`DEQUANTIZE`,
  and `STRIDED_SLICE` with `shrink_axis_mask`) are unsupported and the run
  errors out. MediaPipe's graph keeps blendshapes on the CPU anyway.
- WARP timings (landmarks 402 ms at half precision, 75 to 82 ms at 32-bit,
  against 8.4 ms on CPU) say nothing about a real GPU.

A Windows GPU path would therefore be a LiteRT pipeline with our own pre- and
post-processing, not MediaPipe. It is not planned until a physical Windows GPU
shows a clear speed gain over the CPU.

## Not established

- Any physical GPU, for official 1.0.1, this build or LiteRT.
- Speed: llvmpipe emulates the GPU on the CPU.
- A shippable Linux GPU runtime: it would need OpenCV linked statically, as in
  Google's wheel, and the provenance and fresh-consumer checks the macOS source
  runtime has.

Both workflows are manual:
`gh workflow run desktop-gpu-probe.yaml -f mediapipe_version=1.0.1`,
`gh workflow run linux-gpu-build.yaml` and
`gh workflow run windows-gpu-litert-probe.yaml`. The runs above used them from
scratch branches; the committed versions differ from the final runs' only in
triggers, the manual version default and comments. `sha256.json`
covers the evidence files here.
