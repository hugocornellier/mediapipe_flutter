# MagicTouch macOS validation — 2026-09-12

Apple M4 Max, 16 CPU cores, macOS 26.4 (25E246), Flutter 3.44.8 / Dart 3.12.2.
Implementation commit: `5bc34f0`; subsequent changes are documentation, saved
evidence and formatting. Official MediaPipe 1.0.1, CPU, unchanged MagicTouch
int8 version-1 model.

## Results

- All **122 vision package tests** passed, including existing CPU/Metal face
  regressions, full-pixel segmentation references, stride/ownership/lifecycle,
  face/segmenter coexistence and native archive verification.
- All **8 editor controller/geometry/overlay tests** passed.
- The real macOS editor integration test passed image selection, clear, undo
  and image replacement. [editor.png](editor.png) is captured from that test.
- All **8 existing iOS simulator CPU integration tests** passed on iPhone 17 Pro,
  iOS 26.4; shared image types and task selection remain compatible.
- `make analyze` passed across all packages and examples.
- Fresh candidate and public-release Flutter consumers passed debug and release
  inference with **maximum absolute reference error 0.0** in both selected
  full-mask cases. The package's 11-case reference suite uses a 1e-6 tolerance.
- The isolated consumers contained no local native source/library. Their child
  PATH blocked Python, Bazel, Bazelisk, CMake and Ninja. None was invoked.
  Only the segmenter runtime was downloaded/bundled.

Public native prerelease:
[interactive-segmenter-v1.0.1-1](https://github.com/hugocornellier/mediapipe_flutter_native/releases/tag/interactive-segmenter-v1.0.1-1).
GitHub reports archive digest
`8bec2f56b2f6bf2fa0b31dacc0c84110c24174467d2ab131935c85c89a0e5b14`,
matching the pinned candidate. Both consumers used identical checksums.

## Initial CPU baseline

1200×600 RGBA, official animals image. Each release app measures 5 image
replacements with first strokes, then 5 unrecorded warm-ups, 20 alternating
positive-click histories, and 10 mask conversions/uploads. These are two runs
on this development machine, not controlled thermal or hardware comparisons.

| Stage | Candidate p50 | Public release p50 | Public release p95 |
| --- | ---: | ---: | ---: |
| `setImage` | 0.725 ms | 0.632 ms | 0.987 ms |
| First stroke after image replacement | 192.980 ms | 197.342 ms | 200.599 ms |
| Repeated stroke | 191.600 ms | 197.187 ms | 199.907 ms |
| Overlay conversion and upload | 1.279 ms | 1.413 ms | 1.925 ms |

Task initialization was 70.0 / 70.6 ms. Input buffer copying was 0.167 / 0.190 ms.
API timings include worker transfer, native inference and copied masks. Overlay
timings include a new isolate, threshold conversion, RGBA transfer and
`ui.Image` creation, excluding frame presentation. Debug editor timings are
not directly comparable to these release measurements.

The first/repeated stroke measurements are similar with this runtime. The API
preserves the official stateful session but does not promise a particular
encoder/decoder caching speedup. No internal model stage was replaced or
optimized. The editor bounds pending work so pointer events cannot accumulate
an unbounded inference queue.

GPU is explicitly unavailable: the official macOS 1.0.1 stroke heatmap graph
fails GLSL 330 shader compilation in its OpenGL 2.1 context. This was reproduced
outside the sandbox with the original wheel and valid RGBA input. See
[gpu-probe.log.gz](gpu-probe.log.gz). No CPU fallback is disguised as GPU.

## Reproduction

```sh
make get
make models
make analyze
make check_format
make test_vision
make test_segmenter_prebuilt
cd packages/mediapipe-task-vision/example_segmenter
flutter test --reporter expanded
flutter test -d macos integration_test/editor_test.dart --reporter expanded
```

See [candidate-consumer.json](candidate-consumer.json),
[public-consumer.json](public-consumer.json), [dart-tests.log.gz](dart-tests.log.gz)
and [ios-simulator.json](ios-simulator.json). Native/model source pins are in
the [task guide](../../INTERACTIVE_SEGMENTER.md).
Hosted face GPU tolerance failures already tracked on the parent branch are
not resolved by this change; local regression success does not establish that
all parent-branch CI checks pass.
