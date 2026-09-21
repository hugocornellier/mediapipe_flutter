# Upstream issues and runtime compatibility findings

Last updated: 2026-09-16. These are local observations unless explicitly marked
as an external report. No new upstream issues have been filed from this session.
An exported symbol alone does not establish a working task or platform.

## Validated baseline

Commit `60da77f` passes Linux x64 and Windows x64 CPU CI for all eleven vision
task families: Face Detector, Face Landmarker, Object Detector, Image Classifier,
Image Embedder, Hand Landmarker, Gesture Recognizer, Pose Landmarker, Holistic
Landmarker, Image Segmenter and the legacy Interactive Segmenter. This includes
independent official-Python reference outputs generated on each runner, native
loading, errors, queued disposal, and fresh Flutter debug/release consumers that
are relocated before running real inference.

[Passing desktop run](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/35111596078)
uses pinned official MediaPipe 1.0.0 wheels. Work after that commit is experimental
until the same jobs pass on it.

## UP-001 — KleidiAI SME wrappers can execute non-streaming SVE on Apple M4

**Status:** crash reproduced; isolated compiler-flag workaround verified and
committed in `tool/build_native.py`, with the rebuilt runtime's digest pinned in
`sdk_downloads.dart`. macOS CPU support stays declared unavailable because of the
separate numerical failures in UP-004.

**Affected observation:** macOS arm64, Apple M4 Max, pinned MediaPipe v1.0.0
source revision `6d31f1ebc3284db74d211d62bdc4f0a0c29ea120`, combined CPU/Metal
runtime. EfficientDet-Lite0 Object Detector and EfficientNet-Lite0 Image
Classifier reach the fault. Face Detector and Face Landmarker smokes do not.

Object Detector reproduces outside Dart using
`packages/mediapipe-task-vision/tool/object_detector_probe.cc`. The fault was:

```text
SIGILL
kai_run_lhs_pack_f32p2vlx1_f32_sme+0x20
xnn_compute_inline_packed_qp8gemm
```

Disassembly of the original wrapper has `addvl sp, sp, #-2` at `+0x20`, before
streaming mode is entered. Clang also emits SVE vector operations in this C
wrapper. The working official 1.0.0 Mac wheel's wrapper has scalar code in that
position. The evidence supports automatic vectorization into non-streaming SVE
as the cause; the assembly kernel itself enters streaming mode.

The candidate adds this Bazel flag without modifying upstream source:

```text
--per_file_copt=external/KleidiAI/.*[.]c@-fno-vectorize,-fno-slp-vectorize
```

The candidate wrapper no longer has the trapping prologue. Native Object
Detector CPU inference succeeds, Face CPU/Metal smokes pass, and Image Classifier
and Embedder CPU tests execute without crashing. This does **not** imply that all
their reference comparisons pass.

Candidate SHA-256:
`7133bfed77463171f1af4792d3cbcb8dbbb2bb6d5a37e7aa204be856292b649e`.
Original SHA-256:
`dbc5ea41d10c334e2f7adc9a746f109334d0826abbd9cedd5d03360c8b4f6238`.

The candidate is now the pinned macOS `vision-v1.0.0-1` runtime digest. That
release is still unpublished, so the hook serves it only from a local build.

Local candidate, manifest, smokes and archive:
`build/codex-tmp/vision-no-vectorize/`.
Original library and manifest backup:
`build/codex-tmp/vision-before-sme-fix/`.
The candidate was copied into the package's ignored `build/native/tasks/` for
Dart validation. The compiler flag and runtime pin are committed; the library
itself is not published.

Inspect with:

```sh
xcrun llvm-objdump --disassemble-symbols=_kai_run_lhs_pack_f32p2vlx1_f32_sme build/codex-tmp/vision-no-vectorize/libmediapipe.dylib
```

The upstream genrule retains install name `@rpath/libmediapipe_source.dylib`.
For an isolated native executable, provide that filename as a copy of the
candidate and set `DYLD_LIBRARY_PATH` to its directory. This loader detail is
separate from the illegal instruction.

## UP-002 — XNNPACK's explicit disable branches select the enabled configuration

**Status:** confirmed by inspection of the dependency used by the pinned build.

In `external/XNNPACK/BUILD.bazel`, the `arm_sme_enabled`, `arm_sme2_enabled` and
`kleidiai_enabled` aliases map their `..._explicit_false` branches to
`..._explicit_true`. Consequently these proposed workarounds do not disable the
kernels in this revision:

```text
--define=xnn_enable_arm_sme=false
--define=xnn_enable_arm_sme2=false
--define=xnn_enable_kleidiai=false
```

There is also an apparent `XNN_ENABLE_SRM_SME` typo in the false branch of
`build_defs.bzl`. Do not assume that adding these defines fixes UP-001.

The cached dependency is under
`build/codex-tmp/bazel/d8fd7dbf830ea5ade71924b0dfe6131d/external/XNNPACK/`.
See also the earlier investigation in
`packages/mediapipe-task-vision/tool/OBJECT_DETECTOR.md`; its statement that no
compiler workaround has been found is now superseded by UP-001.

## UP-003 — MediaPipe 1.0.0 float mask accessor aborts for padded rows

**Status:** reproduced through the official 1.0.0 Mac Python API. The scalar
fallback is implemented in both the reference generator and the Dart mask helper,
and Linux/Windows CI exercises it through the Pose and Holistic mask cases.

Positive Pose Landmarker results with noncontiguous float32 masks can terminate
the process when `mask.numpy_view()` calls `MpImageDataFloat32`:

```text
Check failed: 1 == ChannelSize() (1 vs. 4)
mediapipe::ImageFrame::CopyToBuffer()
GenerateContiguousDataArray
GetCachedContiguousDataAttr
MpImageDataFloat32
```

The contiguous-copy path selects the uint8 ImageFrame overload for float data.
Contiguous masks avoid this path. Odd widths and rotated inputs expose it;
testing only widths whose rows require no padding misses the defect.

The reference generator uses `numpy_view()` only for contiguous
masks and official `mask[y, x]` scalar reads otherwise. The Dart helper
`copyVisionConfidenceMask` mirrors that strategy with `MpImageIsContiguous` and
`MpImageGetValueFloat32`, copying every value into owned Dart storage. Both
hosts compare every sampled mask value against the official output.

Reproduce with the official 1.0.0 environment and:

```sh
build/codex-tmp/mediapipe-reference/bin/python -u -B packages/mediapipe-task-vision/tool/generate_landmark_tasks_reference.py
```

The generator now includes the fallback, so its later failure is UP-006. To
reproduce this accessor abort specifically, replace the fallback with
`mask.numpy_view().copy()` in an isolated copy of the generator.

## UP-004 — Mac source CPU outputs differ from the same-version official wheel

**Status:** unresolved compatibility finding, **not yet proven to be an upstream
bug**. Do not silently relax tolerances or regenerate goldens through our own
native wrappers.

After the UP-001 candidate fixes the crash:

```sh
cd packages/mediapipe-task-vision
dart test test/image_tasks_test.dart --reporter expanded --concurrency=1
dart test test/object_detector_test.dart --reporter expanded --concurrency=1
```

Image tasks pass 26 tests and fail four ROI comparisons at the existing `1e-5`
float tolerance / exact quantized-byte comparison. Example classifier ROI score:
official `0.16696061193943024`, source `0.16767385601997375`. A quantized ROI
embedding differs at index 7: official `255`, source `254`.

Object Detector passes 30 tests and fails five CPU comparisons, including
repeated cases in recovery/video tests. Example tie score on `landmark-ex1.jpg`:
official `0.450329452753067`, source `0.4504084587097168`. Metal still passes its
existing reference comparisons. Several raw, unrotated CPU cases also pass.

Image decoding was checked independently: source C API and official Python
produce exactly identical RGBA pixels for `landmark-ex1.jpg` and
`iris-detection-ex2.jpg` (zero differing bytes). Probe:
`build/codex-tmp/desktop/compare_decode.py`.

The four landmark tasks are gated the same way:
`landmarkTaskCapabilitiesForPlatform` covers Linux x64 and Windows x64 only, and
`test/landmark_tasks_test.dart` skips its comparisons on macOS rather than
comparing a different binary's arithmetic.

Preprocessing, compiler behavior, and OpenCV build differences remain candidates
to investigate; none has been established as the cause. These observations do
not affect the passing Linux/Windows official-wheel CI baseline.

## UP-005 — Same-version wheel and source Holistic options have different ABI order

**Status:** confirmed by comparing pinned headers with the official 1.0.0 wheel's
ctypes declarations. Adapter implemented; inference validation pending.

After the three face thresholds, the source `MpHolisticLandmarkerOptions` places
`min_hand_landmarks_confidence` before the three pose thresholds. The wheel places
it after them. Struct sizes match, so using source bindings unchanged can silently
apply the wrong thresholds. Defaults are all `0.5` and conceal the mismatch.

`lib/src/io/holistic_landmarker.dart` adapts the four float slots for Linux and
Windows wheels and retains source order for the Mac source runtime. The reference
generator includes distinct nondefault hand/pose thresholds to exercise this.
Do not modify the generated source struct to wheel order globally.

Wheel declaration:
`build/codex-tmp/mediapipe-reference/lib/python3.12/site-packages/mediapipe/tasks/python/vision/holistic_landmarker.py`.
Source declaration:
`packages/mediapipe-task-vision/third_party/mediapipe/tasks/c/vision/holistic_landmarker/holistic_landmarker.h`.

Other observed wheel/header differences include bool versus int for the ROI
presence flag and an extra source keypoint presence byte in padding. Existing
desktop Face/Object inference tests pass; continue reviewing ABI per new task.

## UP-006 — Holistic mask smoothing retains dimensions across IMAGE requests

**Status:** reproduced in official MediaPipe 1.0.0 Mac Python API. Unresolved
upstream; worked around in the reference generator and in how the tests use the
public wrapper.

Reusing a Holistic task with segmentation masks enabled across differently sized
images, including a rotated image, fails even in IMAGE mode:

```text
SegmentationSmoothingCalculator
RET_CHECK ... current_mat->rows == previous_mat->rows (1000 vs. 667)
```

The failed graph also reports the same error during `close()`, which can mask the
original processing exception.

`tool/generate_landmark_tasks_reference.py` now builds a fresh task for every
IMAGE request and keeps one task only for a VIDEO sequence, which is what IMAGE
mode promises and what `test/landmark_tasks_test.dart` does on the Dart side. The
checked-in reference was regenerated from scratch after that change; the earlier
file, written from incorrectly packed raw fixtures, is gone. A caller that reuses
one Holistic task with masks enabled across differently sized images still hits
this; VIDEO mask processing needs a documented size policy.

## UP-009 — Image Segmenter creation crashes on a null display-names locale

**Status:** reproduced through this repository's Dart bindings against the pinned
1.0.0 runtime. Worked around locally; not reported upstream.

`MpImageSegmenterOptions.display_names_locale` is a `const char*` that
`MpImageSegmenterCreate` dereferences unconditionally, so passing null segfaults
inside task creation rather than returning a status:

```text
si_signo=Segmentation fault: 11(11), si_code=SEGV_ACCERR(2), si_addr=0x0
MpImageSegmenterCreate
```

The equivalent classifier field tolerates null: `classifier_options_c.py` sets
`display_names_locale = None` when no locale is requested, and that path works.
Google's own Image Segmenter bindings never exercise the null case because
`MpImageSegmenterOptionsC.from_c_options` always passes `ctypes.c_char_p(b'')`.

`lib/src/io/image_segmenter.dart` therefore always passes a string, using an
empty one when the caller requests no locale. Review this field for each new
task rather than assuming null is accepted.

## UP-010 — Segmentation tasks reject a region of interest

**Status:** confirmed through the official 1.0.0 Python API; expected behavior
rather than a defect, recorded because the C API accepts the argument.

`MpImageSegmenterSegmentImage` and the legacy Interactive Segmenter both take
`MpImageProcessingOptions`, which carries a rectangle, but supplying one fails:

```text
ValueError: This task doesn't support region-of-interest.
```

Rotation is accepted. The Dart wrappers therefore expose `rotationDegrees` only,
instead of offering a parameter the task rejects at run time.

## UP-007 — Official 1.0.1 Mac detector graphs can abort opening a CPU graph

**Status:** external upstream report, checked 2026-09-16; not reproduced anew in
this session. [MediaPipe issue #6356](https://github.com/google-ai-edge/mediapipe/issues/6356)
is open.

The report concerns macOS arm64, Apple M5, Python 3.14.5, MediaPipe 1.0.1. Face
Detector, Face Landmarker, Hand Landmarker and Pose Landmarker abort opening
graphs with `TensorsToDetectionsCalculator`; its Metal helper requests an
unavailable graph service in a CPU graph. Classifier and Embedder succeed in the
reported tests. Avoid generalizing this report to every task or OS.

This is why the desktop vision baseline pins working 1.0.0 wheels rather than
automatically upgrading everything to 1.0.1. Modern stateful Interactive Segmenter
and modern text tasks have their own runtime requirements.

## UP-008 — Stateful Interactive Segmenter GPU stroke shader fails on macOS

**Status:** prior repository validation, documented for official 1.0.0 and 1.0.1
Mac runtimes; not newly rerun during the desktop work.

`HeatmapFromStrokesCalculatorGl` requests GLSL 330 in a macOS OpenGL 2.1 context.
Shader compilation fails. CPU is validated; GPU is rejected with this specific
reason. This does not imply that Metal or all MediaPipe GPU tasks are broken.

Evidence and prior validation artifacts are documented in
`packages/mediapipe-task-vision/tool/INTERACTIVE_SEGMENTER.md` and
`packages/mediapipe-task-vision/tool/validations/2026-09-12-interactive-segmenter/`.
Morning commit `72711df` corrected attribution to a single runtime version.

## UP-011 — Combined iOS simulator CPU runtime has reference differences beyond face tasks

**Status:** measured compatibility finding on 2026-09-16; not established as an
upstream bug. Face Detector and Face Landmarker remain validated. Other source
task support declarations have not been expanded.

The combined arm64 simulator build exports all 114 declared C functions. Running
all eleven vision task families in a fresh Flutter app with temporary support
overrides in an isolated package copy yields **107 passed, 56 failed, 49 GPU
skips**. The failing comparisons retain the desktop suite's existing tolerances
and exact mask-byte checks. Simulator runtime: iOS 26.4, host: Apple M4 Max.

The first attempt exited during Object Detector CPU inference. Disassembly
showed the same non-streaming SVE prologue described in UP-001. Applying the
existing scoped KleidiAI compiler flag to the iOS build removes those instructions
and allows the complete suite to run without that exit.

The rebuilt simulator library SHA-256 is
`a4fea1f2abddb6d656b043b5471a09a64df1308475422da9800c8f880cd2aa9e`.
Examples: Object Detector score `0.4504084587097168` versus the official
`0.450329452753067`; classifier ROI score `0.16767385601997375` versus
`0.16696061193943024`; normalized quantized ROI embedding byte 7 is `254`
versus `255`. These match UP-004's macOS observations. Hand/Gesture/Pose/Holistic
coordinates or confidences exceed `1e-5` in some cases; confidence mask hashes
also differ. Category-mask cases and many other cases pass.

Reproduction, from the vision package with a booted simulator and downloaded models:

```sh
python3 -B tool/build_ios_simulator.py
python3 -B tool/test_ios_consumer.py --experimental-all-tasks
```

Local evidence: root `build/codex-tmp/ios-consumer-yb2gy4pg/`. The report marks
the capability overrides explicitly; they never modify the consumer package's
real support declarations. Confidence-mask hash comparisons are intentionally
stricter than numerical float comparisons; a failed hash alone does not establish
the size or practical significance of a difference.

An additional lead: the pinned official Mac 1.0.0 wheel embeds a build-information
string naming OpenCV 4.13.0, whereas the local builders pin OpenCV 4.12.0. That
embedded string also describes a Linux x64 build, so it is not sufficient evidence
of the Mac binary's actual build configuration or of a cause for these differences.

## UP-012 — Android combined runtime needs C API export isolation

Observed September 16 with pinned MediaPipe v1.0.0, NDK 28.2.13676358,
OpenCV 4.12.0's Android SDK, and an arm64 Android 16 emulator using 16 KB pages.
The first combined runtime built and exported all 114 C APIs, but the native
face probe crashed before entering inference. The Android crash backtrace ends
at `/system/lib64/libprotobuf-cpp-lite.so (_GLOBAL__I_000101+60)` during linker
constructor initialization. The runtime exported internal C++/protobuf symbols;
this behavior is consistent with symbol interposition against system protobuf.

Upstream's task BUILD applies its existing C API version script only to Linux.
A recorded Android-specific BUILD selection now applies that same map to the
combined library. `-z start-stop-visibility=hidden` also hides linker-generated
`__start_pb_defaults` and `__stop_pb_defaults` symbols. The resulting runtime
exports only the public C APIs and its version definition. Both native CPU face
IMAGE probes then pass on the same emulator. No task source/graph code changed.

The GPU-disabled Android build also fails compiling `gl_texture_buffer_pool.cc`
because it includes `gl_context.h` while `GlVersion` and `GlTextureInfo` are
hidden. The candidate uses Android's normal GL-enabled configuration and
selects CPU delegates for validation. Its probes initialize EGL even with CPU
delegates; a functioning GL context is therefore part of the tested environment.
GPU inference remains unvalidated.

Reproduce with `tool/build_android.py` and `tool/test_android_native.py` in the
vision package; see [the Android guide](packages/mediapipe-task-vision/tool/ANDROID.md).
The passing runtime has SHA-256
`1a01c7ebef93f0a113d8c9714c72b0012198d7dfc7dcff12207db67667de3658`.
Build and smoke receipts are under `tool/validations/2026-09-16-android-native/`.
These probes check loading, ABI and result counts, not Flutter packaging,
numerical reference parity or physical-device performance. Android package
support remains undeclared. This issue has not been filed upstream.

## Integration pitfalls resolved in this repo

These are recorded for continuity, not classified as confirmed MediaPipe defects.

- **Borrowed NumPy image lifetime:** `mp.Image.create_from_file(...).numpy_view()`
  can leave a view whose temporary image owner has been released before `.copy()`
  executes. Linux/Windows reference generation segfaulted. Keep the image in a
  named variable through the copy. Fixed in commit `1d6b57c`; this follows the
  API's ownership contract.
- **Windows Dart executable spelling:** `shutil.which('dart')` resolved uppercase
  `dart.EXE`; the Dart 3.12 hook runner attempted `dart.EXE.exe`. Explicitly launch
  Flutter's `dart.bat` wrapper on Windows. Fixed in `acf6cdd`. The runner's
  extension handling is a potential upstream Dart issue; its exact scope has not
  been independently established.
- **Windows Python output encoding:** Flutter's Unicode build marker failed
  while the harness printed logs through cp1252. Configure stdout/stderr as UTF-8.
  Fixed in `6a1329e`; a harness bug.
- **Raw fixture packing:** the official file decoder returns RGBA. Slice to three
  channels and copy before emitting SRGB fixture bytes. An early landmark
  reference pass used the wrong packing and produced misleading empty results.
  Corrected in the uncommitted generator; replacement goldens are still pending.
- **Gesture category indices:** the C API reports a raw classifier index for
  recognized gestures, and the official Python bindings overwrite it with -1
  because canned and custom classifiers number their labels independently. The
  Dart wrapper reports -1 for the same reason; the documented value is not a
  comparison adjustment.
- **Native asset aliases:** distinct Dart asset IDs cannot share one physical
  library filename. Desktop hooks use separate Face Detector, Face Landmarker
  and combined-vision aliases of the same verified native bytes. Preserve those
  aliases and cache hashes/mtime behavior when adding tasks.
