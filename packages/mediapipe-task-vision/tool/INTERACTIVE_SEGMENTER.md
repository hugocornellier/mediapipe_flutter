# MagicTouch Interactive Segmenter

The optional `InteractiveSegmenter` wraps Google's modern **MediaPipe 1.0.1**
stateful MagicTouch pipeline on **macOS arm64, macOS 14+, CPU**. The complete
official model bundle and native inference graph are preserved. This is the
current image-and-strokes API, not the legacy one-point ROI wrapper.

Official sources:

- [Overview and model](https://developers.google.com/edge/mediapipe/solutions/vision/interactive_segmenter)
- [Python API and full stroke history](https://developers.google.com/edge/mediapipe/solutions/vision/interactive_segmenter/python)
- [MediaPipe 1.0.1 distribution](https://pypi.org/project/mediapipe/1.0.1/)

## Consumer configuration

Opt in from the consuming app's `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    mediapipe_flutter_vision:
      tasks: [interactive_segmenter]
```

You may include `face_detector` and/or `face_landmarker` in the same list.
Omitting configuration still enables only the two existing face tasks. Selecting
the segmenter adds a **32.6 MB compressed runtime** (100.9 MB extracted) from
the pinned public native release. It does not enlarge face-only applications.
Selection is explicit at build time; it is not inferred from Dart imports.
After removing a task, run `flutter clean` to remove stale native frameworks.

Set the host's macOS deployment target to **14.0** and add `ARCHS = arm64` and
`EXCLUDED_ARCHS = x86_64` to `macos/Runner/Configs/AppInfo.xcconfig`.
The upstream wheel's filename says macOS 11, but its actual Mach-O load command
requires 14.0. Intel macOS and iOS are not supported for this task yet.

The model is separate: Google's unchanged **30.5 MB** int8 version-1 bundle:

```sh
dart tool/download_interactive_segmenter.dart
```

The maintainer downloader pins
`interactive_segmenter_v2/magic_touch/int8/1/interactive_segmentation.task`
and verifies SHA-256
`38431bc66b883404e8397f74c3579404315b9b52b04a46c6346fe906a7309b03`.
Consumers supply a model file or bytes, choosing whether to bundle or download
them. Build hooks download native libraries, not models.

## Dart API

```dart
final task = await InteractiveSegmenter.create(
  InteractiveSegmenterOptions(
    modelPath: '/absolute/path/interactive_segmentation.task',
    delegate: VisionDelegate.cpu,
  ),
);
try {
  await task.setImage(VisionImage.fromFile('/absolute/path/photo.jpg'));
  final history = [
    SegmentationStroke(
      brushMode: SegmentationBrushMode.positive,
      points: [SegmentationPoint(x: 0.66, y: 0.55)],
    ),
  ];
  final mask = await task.segment(history);
  // Unmodified float32 foreground confidence at (x, y):
  print(mask.confidence[100 * mask.width + 150]);
} finally {
  await task.dispose();
}
```

Use `modelBytes` for Flutter assets. `setImage` also accepts RGB/RGBA/BGRA pixels
with optional row padding. The wrapper removes padding and converts BGRA;
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

## macOS editor

Run `make example_segmenter` from the repository root. The separate
[`example_segmenter`](../example_segmenter/) app supports sample photos, opening
JPEG/PNG files, include/exclude/lasso strokes, undo, clear and a display-only
threshold slider. It decodes the image once with Flutter and sends those exact
oriented pixels to MediaPipe, so canvas coordinates match the input.

Inference has one active request and one replaceable pending history. Drawing
does not enqueue every pointer event. Image replacement, undo and clear discard
obsolete results. Mask coloring runs off the UI isolate. Timings show the
public async inference call and mask conversion/upload separately.
This is a still-image editor; camera capture and temporal object tracking are
not part of the Interactive Segmenter API.

## GPU status

`VisionDelegate.gpu` fails explicitly for this task. The official 1.0.1 macOS
runtime's `HeatmapFromStrokesCalculatorGl` requests GLSL 330 in a macOS OpenGL
2.1 context and fails to compile its shader. This was reproduced using the
official Python API with valid RGBA input outside the sandbox.
Enabling Metal for the face tasks does not repair this separate stroke graph.
There is no silent CPU fallback and no modified substitute pipeline.

## Native provenance

The modern stateful symbols are present in Google's official wheel while the
public C/C++ source API still describes the legacy segmenter. The package uses
the pinned full **1.0.1 macOS arm64 wheel runtime**, with Dart FFI declarations
adapted from that wheel's official ctypes definitions. Tests compare ABI sizes
and field offsets with metadata generated from those definitions.

`python3 -B tool/prepare_interactive_segmenter.py` prepares a candidate archive
and provenance from the pinned wheel. It retains the full LICENSE and NOTICE.
The wheel's dylib has too little header space for Flutter's rewritten install
name. Packaging shortens only equivalent absolute system-framework paths and
re-signs the library ad hoc. It verifies unchanged section layout and every
payload byte from the first section to the code signature. Native code, data,
model inference and task behavior remain unchanged; load/signing metadata does
change. Original wheel/library digests and prepared-library digests are recorded
separately. `macho_metadata.py` documents these checks.

The build hook verifies the compressed archive, prepared library, manifest,
platform, CPU-only capability and license digests. Extraction allows only the
four expected regular files. Corrupt caches are repaired from verified bytes.
Consumers need Flutter/Xcode, but no Python, Bazel, CMake or credentials for
native downloads. Source access still follows this private repository's policy.

## Validation and measurements

- `dart test test/interactive_segmenter_test.dart` compares every mask pixel in
  11 cases with Google's 1.0.1 Python API at maximum absolute error 1e-6:
  clicks, partial strokes, multiple selections, exclusion, lasso, undo, image
  replacement, blank input, padded RGB/RGBA/BGRA, ownership and lifecycle.
  It also runs the segmenter alongside CPU and Metal face tasks.
- `dart test test/native_assets/interactive_segmenter_library_test.dart`
  checks real artifact installation, offline reuse, cache repair, checksums,
  provenance, licenses and unsafe archive rejection.
- `cd example_segmenter && flutter test` checks the bounded queue, late-result
  rejection, undo/clear, lasso completion, letterboxing and display threshold.
- `python3 -B tool/test_segmenter_macos.py` creates an isolated consumer with
  no local native source/library, downloads the public archive and verifies
  debug and release inference against full reference masks. Its child PATH
  blocks Python, Bazel, Bazelisk, CMake and Ninja. The release app records input
  copy, image replacement, first stroke, repeated strokes and overlay timings.
- Before publishing, pass
  `--local-release build/releases/interactive-segmenter-v1.0.1-1` to run the
  same checks against a loopback-served candidate with unchanged checksums.

Reference generation requires the original **1.0.1** Python distribution;
face references continue to use **1.0.0**. Use a separate environment, or pass
`--python-package-root` to `generate_interactive_segmenter_reference.py` with
the fully extracted pinned wheel. Ordinary consumer/test inference never loads
Python. Fixture attribution and ABI provenance are in
[the reference notes](../test/fixtures/interactive_segmentation/README.md).
