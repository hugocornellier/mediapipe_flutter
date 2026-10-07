# MagicTouch Interactive Segmenter

`InteractiveSegmenter` wraps Google's stateful MagicTouch pipeline: the
current image-and-strokes API, not the legacy one-point ROI wrapper. The
complete official model bundle and native inference graph are preserved. It
runs through Google's own runtime on each platform:

- **Android, iOS, macOS arm64 (14+), Linux x64:** Google's 1.1.0 vision
  library, which the vision package's hook bundles.
- **Web:** `@mediapipe/tasks-vision` 1.0.1.

Browsers run it on CPU or WebGL 2, every other platform on the CPU. Google's
Windows library does not export the stateful API, so Windows has no
Interactive Segmenter.

Official sources:

- [Overview and model](https://developers.google.com/edge/mediapipe/solutions/vision/interactive_segmenter)
- [Python API and full stroke history](https://developers.google.com/edge/mediapipe/solutions/vision/interactive_segmenter/python)
- [MediaPipe 1.0.1 distribution](https://pypi.org/project/mediapipe/1.0.1/)

## Consumer configuration

Bundle Google's model with the app in its `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/mediapipe/

hooks:
  user_defines:
    mediapipe_vision:
      models: [interactive_segmenter]
```

Then run `dart run mediapipe_core:bundle_models` from the app's root. The model
is Google's unchanged **30.5 MB** int8 version-1 bundle
(`VisionModels.interactiveSegmenter`,
`interactive_segmenter_v2/magic_touch/int8/1/interactive_segmentation.task`,
SHA-256 `38431bc66b883404e8397f74c3579404315b9b52b04a46c6346fe906a7309b03`).
Maintainers download it with `dart tool/download_interactive_segmenter.dart`.

No platform needs a setting. The task needs no entry in
`mediapipe_vision.tasks`, and a Windows build fails if that list names it.

On macOS, set the deployment target to **14.0** and add `ARCHS = arm64` and
`EXCLUDED_ARCHS = x86_64` to `macos/Runner/Configs/AppInfo.xcconfig`; Google's
library requires macOS 14.0. Intel Macs are not supported.

## Dart API

```dart
final task = await InteractiveSegmenter.create(
  InteractiveSegmenterOptions(
    model: VisionModels.interactiveSegmenter,
    delegate: Delegate.cpu,
  ),
);
try {
  await task.setImage(VisionImage.fromFile('/absolute/path/photo.jpg'));
  final history = [
    Stroke(
      brushMode: BrushMode.positive,
      points: [const NormalizedKeypoint(x: 0.66, y: 0.55)],
    ),
  ];
  final mask = await task.segment(history);
  // Unmodified float32 foreground confidence at (x, y):
  print(mask.confidence[100 * mask.width + 150]);
} finally {
  await task.dispose();
}
```

`modelPath` or `modelBytes` take a model of your own instead of the bundled
one. `setImage` also accepts RGB/RGBA/BGRA pixels with optional row padding. The wrapper removes padding and converts BGRA;
Google's pipeline performs all model preprocessing and inference.

Call `setImage` once per image, then pass the **complete current stroke history**
to every `segment` call. Points are normalized to the input image, excluding
canvas letterboxing. A positive click is a one-point positive stroke. Negative
strokes exclude areas; lasso strokes have at least three points. Set
`isCompleted: false` while drawing and resubmit the finished stroke with
`isCompleted: true` when released. Undo by resubmitting a shorter history.

Clear the displayed mask when the history becomes empty, and call `setImage`
to reset the session. Empty histories are rejected before native execution:
the upstream decoder fails with an input tensor count mismatch on empty input.
After a native segment error, a new successful `setImage` is required.
Validation errors do not poison the native session.

The persistent worker serializes requests in submission order. Results own
their confidence buffers and remain valid after another inference or disposal.
No threshold, smoothing or postprocessing is added to the task result.
`dispose` drains queued work and is idempotent.

## Editor

The gallery's Segment page (`gallery/lib/segment_page.dart`, with its editor in
`gallery/lib/segment/`) is the MagicTouch editor on every platform: include
strokes, undo, clear and a display-only threshold setting on the bundled
sample photo. The tap area takes the picture's exact shape, so a tap's
position is measured against the picture, not the letterbox.

Inference has one active request and one replaceable pending history. Drawing
does not enqueue every pointer event. Image replacement, undo and clear discard
obsolete results. Mask coloring runs off the UI isolate. Timings show the
public async inference call and mask conversion/upload separately.
This is a still-image editor; camera capture and temporal object tracking are
not part of the Interactive Segmenter API.

## GPU status

`queryInteractiveSegmenterCapabilities()` (exported by
`mediapipe_vision.dart`) returns supported delegates,
required macOS version/architecture and unavailable-delegate explanations. It
does not load a model. Creation checks the same support information before
starting a worker. The shared
[four-task validation tool](../../../tool/task_benchmarks/README.md) measures
repeated strokes, image replacement, reloading and process memory alongside the
three modern text tasks.

`Delegate.gpu` runs in browsers only, on WebGL 2 as Google's sample does;
elsewhere `create` refuses it with a `RuntimeUnavailableException`. Google's
mobile SDKs run the task on the CPU. On macOS, Google's
`HeatmapFromStrokesCalculatorGl` requests GLSL 330 in a macOS OpenGL 2.1
context and fails to compile its shader, in both the 1.0.0 and 1.0.1 runtimes
(upstream-issues.md UP-008). This was reproduced using the official Python API
with valid RGBA input outside the sandbox. Linux's GPU path aborts (UP-029).
Enabling Metal for the face tasks does not repair this separate stroke graph.
There is no silent CPU fallback and no modified substitute pipeline.

## Native provenance

The modern stateful symbols are present in Google's official libraries while
the public C/C++ source API still describes the legacy segmenter. The package
binds them in Google's vision library
(`package:mediapipe_vision/mediapipe.dylib`) on macOS, Linux and iOS. The Dart
FFI declarations
(`lib/src/third_party/mediapipe/interactive_segmenter_bindings.dart`) are adapted
from the official ctypes definitions. Tests compare ABI sizes and field
offsets with metadata generated from those definitions.

The vision package's hook bundles Google's library unmodified except on macOS,
where it shortens the system framework paths and signs the copy again to make
room for Flutter's install name
([UP-042](../../../upstream-issues.md#up-042-per-family-macos-and-simulator-libraries-have-no-header-room-for-a-rename)).
Consumers need Flutter and Xcode, but no Python, Bazel, CMake or credentials
for native downloads.

## Validation and measurements

The saved macOS validation and CPU baseline, in git history at `3e217ac` under
`tool/validations/2026-09-12-interactive-segmenter/`, include the public-release
consumer report and editor screenshot.

- `dart test test/interactive_segmenter_test.dart` compares every mask pixel in
  11 cases with Google's Python API (the 1.1.0 wheel) at maximum absolute
  error 1e-6: clicks, partial strokes, multiple selections, exclusion, lasso,
  undo, image replacement, blank input, padded RGB/RGBA/BGRA, ownership and
  lifecycle. It also runs the segmenter alongside CPU and Metal face tasks.
- `gallery/test/segment_editor_controller_test.dart` checks the editor's
  bounded queue, late-result rejection, undo/clear, lasso completion, the ring
  a tap becomes and the display threshold. The gallery journey
  (`gallery_journey_test.dart`) draws, undoes and clears on the Segment page.
- The gallery's `sdk_interactive_segmenter_test` runs it on the iOS
  Simulator.

`generate_interactive_segmenter_reference.py` runs Google's wheel pinned for
the host (core's `tool/official_wheels.py`); `--python-package-root` takes the
fully extracted pinned wheel instead. Ordinary consumer/test inference never
loads Python. Fixture attribution and ABI provenance are in
[the reference notes](../test/fixtures/interactive_segmentation/README.md).
