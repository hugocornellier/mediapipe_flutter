# Segmenter brushes

Planned, not started: the Interactive Segmenter task takes all three of
Google's brush modes on every platform it supports, but the gallery's
MagicTouch editor offers only Include. Found on 2026-10-06 at `bbf198c`. Paths are from
the repository root. Check a finding again before building on it.

## Goal

Offer Include, Exclude and Lasso again in the gallery's Segment page, on every
platform the task supports, once Exclude and Lasso are checked as thoroughly
as Include.

## Today

**The task** takes every mode. `BrushMode` has `positive` (Include), `negative`
(Exclude) and `lasso`, with Google's numeric values, and `Stroke` rejects a
lasso of fewer than three points
(`packages/mediapipe-task-vision/lib/src/types/strokes.dart`). Each platform
passes the mode through to Google's runtime:

- **Android, iOS, macOS, Linux:** the C API, through FFI.
- **Web:** vision's `assets/worker.js`, which passes Google's numeric values.
- **Windows:** no Interactive Segmenter at all; Google's Windows library does
  not export the stroke API.

**The editor** hides the selector, and the code that hides it carries the
TODO: `gallery/lib/segment_page.dart` offers no selector, with its editor in
`gallery/lib/segment/editor_controller.dart`.

The editor already handles the other modes: a lasso needs three points, so a
tap does nothing, and the stroke is closed when it completes. The page has
hints for Exclude and Lasso (`_hintFor`). Restoring the selector is a
`SegmentedButton<BrushMode>` that sets `editor.brush`.

**History:** vision's former `example_segmenter` app dropped to Include in
`b792b05` (2026-09-16: "the MagicTouch editor keeps only the Include brush for
now"), and the gallery's TODO came with `ac8d13e` (2026-09-29). The example
app was folded into the gallery before the 0.1.0 release. No failure is recorded for either mode:
neither commit nor `upstream-issues.md` names a bug. The TODOs asked for more
testing.

## How well each mode is checked

| Platform | Include | Exclude | Lasso |
| --- | --- | --- | --- |
| macOS, Linux x64 (CPU) | Pixel-compared with Google | Pixel-compared with Google | Pixel-compared with Google |
| Android, iOS (CPU) | Compared with Google | Only "does not grow the mask" | Only "selects something" |
| Web (CPU, WebGL) | Exercised | No test | No test |
| Windows | No task | No task | No task |

- **macOS and Linux:** `packages/mediapipe-task-vision/test/interactive_segmenter_test.dart`
  compares every mask pixel with Google's Python API (the reference wheel) at
  maximum absolute error 1e-6, in 11 cases that include exclusion and lasso
  (`test/fixtures/interactive_segmentation/`: `raw-negative.f32.gz`,
  `raw-lasso.f32.gz`, `official_reference.json`). Linux runs it through
  `packages/mediapipe-task-vision/tool/test_desktop.py` in
  `.github/workflows/desktop.yaml`.
- **Android and iOS:** `gallery/integration_test/sdk_interactive_segmenter_test.dart`
  compares the Include selection with Google's reference (grid error under
  0.02), but only checks that an Exclude stroke leaves the mask no larger
  than Include alone (plus 0.001) and that a lasso selects more than 1% of the
  image.
- **Web:** the browser journey (`gallery/tool/browser/test_gallery_journey.mjs`)
  draws on the gallery's Segment page, which offers Include only. The manual
  probe `gallery/tool/web_api_probe.dart` sends one Exclude stroke, and
  nothing sends a lasso. Vision's browser tests (`test/web/`) send neither.
- **The editor:** `gallery/test/segment_editor_controller_test.dart` covers
  Exclude and Lasso against a fake backend, including lasso completion and
  undo.

## Done when

- Exclude and Lasso are compared with Google's reference masks on Android,
  iOS and web, as macOS and Linux already are. The macOS and Linux fixtures
  already hold both cases; `gallery/tool/generate_sdk_references.py` and
  `gallery/integration_test/support/official_mask_references.dart` hold the
  gallery's references.
- The editor offers the selector again, and the doc that describes Include
  only says otherwise: the editor section of
  `packages/mediapipe-task-vision/tool/INTERACTIVE_SEGMENTER.md`.

## Not tried

- Drawing Exclude or Lasso through the editor's UI on Android, iOS or the
  web; only the task API and the editor's controller were tested with them.
