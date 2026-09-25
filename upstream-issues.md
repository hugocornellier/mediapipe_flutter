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

## UP-005: Google's Python writes Holistic thresholds in the wrong order

**Status:** confirmed 2026-09-24 on the macOS 1.0.0 wheel and 1.1.0rc20260924
nightly, and on the pinned Linux 1.0.1 and Windows 1.0.0 wheels (CI run
36009377156). Fixed in this repository; not reported upstream.

After the three face thresholds, the public header's `MpHolisticLandmarkerOptions`
places `min_hand_landmarks_confidence` before the three pose thresholds. The
wheels' Python ctypes place it after them. The compiled library, including the
wheels' own copy, reads the header's order, so Google's Python applies every
non-default threshold to the wrong field: pose detection lands on the hand
threshold, suppression on pose detection, pose landmarks on suppression, and hand
on pose presence. The defaults are all `0.5` in both APIs, which hides it.

`tool/holistic_threshold_order_probe.py` shows this by setting one threshold at a
time to an extreme value on `pose.jpg`: only the header's arrangement makes each
option act on its own field. The Dart wrapper
(`lib/src/io/holistic_landmarker.dart`) now writes the header's order on every
platform. It previously copied the Python order on Linux, Windows and the official
macOS runtime, and CI could not see it because the references came from the same
Python. `tool/generate_landmark_tasks_reference.py` now rearranges Python's slots
into the header's order before creating tasks, and asserts the ctypes still use
the old order so a fixed wheel fails loudly. Its non-default case (hand 0.99)
now drops both hands, as the option promises.

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

## UP-013 — Holistic IMAGE results depend on earlier IMAGE calls

**Status:** reproduced September 23 in Google's official 1.0.0 macOS Python
wheel and the iOS 1.0.1 SDK. Unresolved upstream; the tests work around it.

One Holistic task given the same image four times in IMAGE mode returned
landmarks 0.033 to 0.050 apart from its first result (Python wheel), and 0.0078
apart on the iOS simulator. A fresh task's first call is exactly repeatable.
IMAGE mode should not carry state between calls. `sdk_landmark_tasks_test.dart`
and the web API probe compare only fresh tasks' first results for Holistic.

## UP-014 — iOS Holistic rejects rotated images

**Status:** observed September 23 with Google's 1.0.1 iOS XCFrameworks.
Worked around in the iOS adapter.

`MPPHolisticLandmarker` fails any image whose orientation is not
`UIImageOrientationUp` ("Unsupported UIImageOrientation"), unlike the other iOS
tasks and unlike Holistic on every other platform. The adapter
(`native/ios/face_sdk_bridge.mm`) turns the pixels itself and maps the points
back into the caller's frame. On an iPhone 15 Pro the result is 0.008 (CPU) and
0.010 (Metal) from Google's rotated desktop reference.

## UP-015 — Pose GPU treats rotated input differently from Pose CPU

**Status:** reproduced September 23 in Google's official 1.0.0 macOS wheel and
on an iPhone 15 Pro with the 1.0.1 iOS SDK. Unresolved upstream; recorded, not
worked around.

Upright, Pose CPU and GPU agree to 0.005 (wheel, Metal) and 0.014 (iPhone).
Given the same image turned a quarter with `rotation_degrees = 90`, they differ
by 0.16 (wheel) and 0.22 (iPhone, against the CPU reference). CPU output is also
not a plain rotation of the upright result. Hand, Gesture and Holistic show
neither effect. The SDK tests require the rotated reference on the CPU only for
Pose and record the GPU value.

## UP-016 — Android 1.0.0 declares protobuf-javalite but needs protobuf-java

**Status:** reported upstream as
[google-ai-edge/mediapipe#6348](https://github.com/google-ai-edge/mediapipe/issues/6348)
and [#6364](https://github.com/google-ai-edge/mediapipe/issues/6364).
Worked around in `mediapipe_flutter_vision_android`.

`tasks-core` 1.0.0's POM declares `protobuf-javalite` 4.26.1, but
`HolisticLandmarkerOptions` calls `Any$Builder.build()` with full protobuf-java's
signature, so Holistic creation fails with `NoSuchMethodError`. No other task
makes that call. The plugin excludes javalite and depends on `protobuf-java`
4.26.1; Face, Hand, Pose, Gesture and Holistic all pass on the emulator with it.

## UP-017 — Image Segmenter stretches the upright mask over a rotated input

**Status:** reproduced September 23 in Google's official 1.0.0 macOS Python
wheel and the iOS 1.0.1 SDK. Unresolved upstream; the package returns what
Google's runtimes return.

Given a rotated input and `rotation_degrees`, Image Segmenter segments the
upright image, then resizes that upright mask to the input's width and height
instead of turning it back. For `landmark-ex1.jpg` turned a quarter turn, the
returned category mask agrees with the upright mask turned back on 37% of
pixels, and with the upright mask resized to the input's shape on 99% (90°:
0.990, 270°: 0.992, 180°: 0.987, which also comes back unflipped). Pose and
Holistic masks do turn back correctly (mean difference 0.003 to 0.007), as
do Interactive Segmenter Legacy's (97% of pixels at 90° and 270°).
`sdk_segmenter_test.dart` checks rotated inputs against the resized upright
mask, and the desktop fixture records the same bytes as Google's wheel.

## UP-018 — Mobile SDKs mishandle padded rows in CPU pose masks

**Status:** observed September 23 with Google's 1.0.1 iOS XCFrameworks on the
simulator (CPU) and Android tasks-vision 1.0.0 on the emulator (CPU). Worked
around in the iOS adapter; Android fails inside Google's code. Metal and the
Android GPU are unverified.

MediaPipe's CPU image frames pad each row to 16 bytes, so a float32 mask whose
width is not a multiple of 4 has padded rows. `MPPPoseLandmarker` and
`MPPHolisticLandmarker` copy a mask as its first width x height floats, so each
row after the first starts further into the previous one. Pose's mask for
`pose.jpg` turned a quarter turn (667 wide) was 0.103 from the upright mask
turned back; read at the padded stride of 668, it is 0.0074, as in Google's
Python wheel. The adapter lays CPU pose masks back out at the padded stride;
the last few values, past the SDK's copy, repeat the row above.

On Android, `PoseLandmarker.detect` itself throws while converting such a mask
("ImageFrame must store data contiguously to be allocated as ByteBuffer"), so
no mask reaches the plugin. `sdk_landmark_tasks_test.dart` expects that error
for the 667-wide case. Holistic's masks take another path and are unaffected
on Android. Camera frames are rarely affected on either platform, since their
widths and heights are multiples of 4.

## UP-019 — Android Image Segmenter reports no labels

**Status:** observed September 23 with Android tasks-vision 1.0.0. Worked
around in `mediapipe_flutter_vision_android`.

`ImageSegmenter.getLabels()` returns an empty list for DeepLab-v3, whose
metadata carries 21 labels (the C API and the iOS SDK report them). Google's
`populateLabels` reads them from the segmentation calculator's options in the
graph config, which `Graph.getCalculatorGraphConfig()` parses with
`ProtoUtil.getExtensionRegistry()`, an empty registry, so the options extension
holding the labels is never read. The plugin parses those options again with
the extension registered and gets all 21 labels in mask order.

## UP-020 — Android Interactive Segmenter Legacy ignores the region of interest

**Status:** observed September 23 with Android tasks-vision 1.0.0 on the
emulator (CPU). Unresolved upstream; the Android adapter does not serve the
task.

`InteractiveSegmenterLegacy.segment(image, roi, options)` returned the same
mask for keypoints (0.5, 0.4), (0.05, 0.05), (0.95, 0.95) and (0.2, 0.8), and
for a one-point scribble: 99.6% of the portrait sample selected, where
Google's Python wheel, the iOS SDK and the browser select the subject (57%)
under (0.5, 0.4). It is the same with Google's declared protobuf-javalite
instead of this plugin's protobuf-java (UP-016). On Android,
`InteractiveSegmenterLegacy.create` throws UnsupportedError rather than
return wrong masks.

## UP-021 — Browser Interactive Segmenter Legacy drops a model buffer

**Status:** observed September 23 with Google's tasks-vision 1.0.1 web bundle in
Chrome. Worked around in the browser worker.

`InteractiveSegmenterLegacy.createFromOptions` with
`baseOptions.modelAssetBuffer` fails in the graph ("ExternalFile must specify
at least one of 'file_content', 'file_name', ..." from
`image_segmenter_graph.cc`), while the same model as `modelAssetPath` loads.
Every other task accepts a buffer. The worker hands this task its bytes as a
temporary Blob URL.

## UP-022: Android Interactive Segmenter drops a model buffer

**Status:** observed September 23 with Google's tasks-vision 1.0.0 Android
library on an x64 emulator. Worked around in the Android plugin.

The stateful `InteractiveSegmenter.createFromOptions` with
`BaseOptions.setModelAssetBuffer` fails with the same "ExternalFile must
specify at least one of 'file_content', 'file_name', ..." error as UP-021,
while the same model as an absolute `setModelAssetPath` loads and matches
Google's reference. The plugin writes this task's bytes to a private file in
the app's cache directory and deletes it when the task closes. Unlike UP-020,
this task follows its strokes.

## UP-023: Android Image Segmenter GPU aborts on a PowerVR GPU

**Status:** observed September 23 on a physical Galaxy A12 (PowerVR Rogue
GE8320, Android 12) in Firebase Test Lab, with Google's tasks-vision 1.0.0.
Not worked around: the abort happens inside Google's native code, which the
plugin cannot catch.

Image Segmenter on the GPU delegate terminates the app while Google's Java
task converts the result: `PacketGetter` aborts with `image_frame.cc:298]
Invalid format: UNKNOWN`. The same test passed on CPU on that phone (every
category cell agreed with Google's reference), and on GPU on a Pixel 8a (Mali)
and a Galaxy S24 (Adreno) the task ran. Apps that offer Image Segmenter on GPU
should expect this on PowerVR devices and prefer CPU there.

## UP-024: Android Image Segmenter GPU category mask is one class low on Adreno

**Status:** observed September 23 on a physical Galaxy S24 (Adreno 750,
Android 16) in Firebase Test Lab, with Google's tasks-vision 1.0.0. Not worked
around; the SDK test recognises it.

On the GPU delegate, DeepLab-v3's category mask labels the person in
portrait.jpg as class 14 instead of 15. The class shares are otherwise right
(0.499 background, 0.501 "14" against Google's GPU reference 0.498 and 0.502
for 15), and the confidence masks match that reference within 0.0015 on
average, so only the category values are off by one. Google's wheel on a Mac's
Metal GPU and its Android SDK on a Pixel 8a's Mali GPU report 15. The byte
already arrives as 14 from Google's Java task. The shape suggests a normalized
class value truncated when the GPU result is read back. Apps that need exact
classes on GPU can take the most confident class from the confidence masks.

## UP-025: Windows task closes wait for Google's usage-logging upload

**Status:** observed September 24 with Google's official 1.0.0 Windows wheel
on GitHub's windows-2025 runners, first as two 30 s test timeouts in a
[desktop run](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/36004929701).
Worked around in CI by blocking the endpoint. The package cannot turn the
logging off.

Google's native library carries a Clearcut usage-logging client: its embedded
source paths include
`mediapipe/tasks/cc/core/logging/google_internal/clearcut_logging_client.cc`,
and the C header describes `MpBaseOptions.ca_bundle_path` as the "CA bundle to
use for usage logging". It posts to `https://play.googleapis.com/log` through
WinINet, and a task's close waits for the upload.

With the endpoint reachable, the median close took 62 ms in
[one probe run](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/36019400724)
and 125 ms in
[another](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/36022472695),
where `curl` to the same endpoint took 0.12 to 0.14 s. Some closes waited 20
to 34 s: 13 of 648 in the first run, and 1 of 485 in the second, where one
more had not returned when its test run ended. Stack dumps taken 5 and 15 s
into those waits show the closing thread blocked in `WaitForSingleObjectEx`
under `MpHandLandmarkerClose` (or the task's own close), a library thread
blocked in `WININET!HttpSendRequestA`, and almost no CPU use: under 0.1 s per
thread between the two dumps. The endpoint also answered some uploads with
HTTP 503. With `play.googleapis.com` resolved to an unroutable address
([run](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/36023936830)),
486 closes took a median of 9 ms and at most 34 ms, and no test timed out.

The factory that creates the client has no switch; it falls back to a no-op
client only when its log store cannot be created. Google's Python wrapper
fills the same logging fields and offers no opt-out. On Windows, `dispose()`
lasts as long as the upload; blocking the host removes both the upload and
the wait. The Linux 1.0.1 library contains the same uploader (over libcurl,
with `ca_bundle_path` as its CA file); no slow close has been seen on Linux.

## UP-026: Holistic cannot open its face blendshapes model on a desktop GPU

**Status:** observed September 25 through Google's own Python API with the
official 1.0.0 macOS wheel (on a hosted macos-15 runner and on macOS 27) and
the official 1.0.1 Linux wheel (OpenGL ES on Mesa, renderer renamed as in the
desktop GPU job). Holistic stays on CPU on desktop.

`HolisticLandmarker` on the GPU delegate fails when its graph opens, in the
inference calculator of the face blendshapes subgraph, whether or not
blendshapes or the segmentation mask are requested. On Metal:
`inference_calculator_metal.cc:284 TFLGpuDelegateBindMetalBufferToTensor(...)
== true (0 vs. 1)`. On Linux the same node fails to open while reporting a
tensor of shape `[52, 1, 1, 1]`, the blendshapes model's. Face Landmarker's own
blendshapes run on these GPUs, so the gap is Holistic's graph.

## UP-027: Linux Image Embedder aborts on OpenGL ES

**Status:** observed September 25 with the official 1.0.1 Linux wheel on a
hosted ubuntu-24.04 runner (Mesa, renderer renamed as in the desktop GPU job),
through Google's own Python API. The package keeps the Linux embedder on CPU;
it runs on Metal on macOS.

`ImageEmbedder` with the GPU delegate aborts the process (SIGABRT) during its
first embeds, with glibc reporting `corrupted size vs. prev_size while
consolidating`. Google's Python also declares the embedding result with the
wrong layout and overruns it on every embed (the text package's
`tool/official_embedding_layout.py`; the vision image generator now corrects
it too), but correcting that layout in the probe changed nothing: the GPU path
still aborts. The classifier, segmenter and detector run on the same GPU.

## UP-028: Pose segmentation masks fail on Metal

**Status:** observed September 25 through Google's own Python API with the
official 1.0.0 macOS wheel, on a hosted macos-15 runner and on macOS 27. The
package refuses the combination with an explanation instead of failing on the
first frame; Pose landmarks run on Metal.

With `output_segmentation_masks` on, `PoseLandmarker` fails on its first
frame in `TensorsToSegmentationCalculator`:
`tensors_to_segmentation_converter_metal.cc:223 upsample_program_ Problem
initializing the program`. Without masks the task runs on Metal. On Linux's
OpenGL ES path the masks work, and so does Image Segmenter's own mask
conversion on Metal.

## UP-029: Linux stateful Interactive Segmenter aborts on OpenGL ES

**Status:** observed September 25 with the official 1.0.1 Linux wheel on a
hosted ubuntu-24.04 runner (Mesa, renderer renamed), through Google's own
Python API. The package keeps the task on CPU on Linux, as on macOS (UP-008).

Segmenting a positive stroke with the GPU delegate aborts the process with
glibc's `corrupted size vs. prev_size while consolidating`. The browser task
runs the same model on WebGL 2.

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
