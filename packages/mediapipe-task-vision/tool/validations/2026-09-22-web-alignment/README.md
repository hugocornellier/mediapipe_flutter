# Web overlay-alignment validation, 2026-09-22

[Passing hosted run 35717731096](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/35717731096)
of the `Web FaceLandmarker` workflow, `browser` job on `ubuntu-24.04`, for
commit `65778cd`. Test: `gallery/tool/browser/test_browser.mjs`, camera
suite, full Chromium 153.0.8010.12 headless with SwiftShader WebGL.

The suite opens the release gallery with Chrome's file-backed fake webcam
(the portrait/blank/portrait Y4M from `gallery/tool/browser/prepare_camera.py`)
and runs the live Face Landmarker on the CPU delegate. After 12 processed
frames with 478 landmarks, the new check mirrors the Dart oracle
(`gallery/integration_test/support/alignment_oracle.dart`):

1. hides the overlay with the Connections toggle;
2. reads where the web view's painter draws the nine alignment probes, which
   the view publishes on the video element from the painter's own
   `PreviewTransform`, relative to the overlay's box on the page;
3. screenshots exactly that box;
4. runs Google's official JS `FaceLandmarker` in IMAGE mode on the screenshot
   inside the page;
5. requires a median deviation of at most 1.5% of the preview diagonal and no
   probe beyond 3%.

Result in CI:

- One face in the 748x560 crop at device pixel ratio 1. Overlay box
  [266.67, 56, 746.67, 560] CSS px; the video element sits within 0.02 px of
  it, so the video really is under its overlay.
- Median deviation 0.0035 of the preview diagonal, maximum 0.0141 (chin).
  Mirrored hypothesis 0.0463.
- Mirror true, rotation 0: the web view mirrors the overlay for the front
  camera because the video element is shown with `scaleX(-1)` while frames
  reach the task unmirrored. That rule is now confirmed against the on-screen
  pixels.
- The probes moved at most 0.94 CSS px between the reads before and after
  the capture.
- All 17 checks passed; the official JS reference error stayed zero for
  landmarks, blendshapes and matrix.

## Finding: the oracle compared mirrored previews under the wrong labels

The first run failed a correctly placed overlay: midline probes (nose,
forehead, chin) agreed to 0.3% to 1.5%, while paired probes (eye corners,
irises, mouth corners) were 8% to 17% off, and neither hypothesis fitted
(median 8.6%, mirrored 4.7%). The screenshot showed the portrait mirrored, as
intended. The cause is how the IMAGE task labels a mirrored face: it names
landmarks by the side of the picture they appear on. `label-swap.json`
(produced by `label_swap_probe.mjs`, same official runtime) runs the task on
the fixture and on its horizontal flip. The flip's landmark 33 lies 17.6% of
the diagonal from the reflection of the original's 33, and 0.3% from the
reflection of its partner 263; every paired probe behaves the same way.

So on any preview that mirrors the frame the task analysed (web, the Android
front camera, Windows), the on-screen landmark under the live landmark's
label is its left/right partner, and the old index-for-index comparison
fails a correct overlay. Both oracles now read each hypothesis under the
labels it implies. Unmirrored previews (Linux, iOS) keep the identical direct
comparison; only their mirrored-hypothesis figure changes definition. The
Linux job on the same commit
([run 35717731384](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/35717731384))
reports median 0.24%, unchanged, and mirrored 4.8% (8% before). A wrong
mirror moves every probe by twice the face's distance from the frame's
centre line, which is about 5% of the diagonal for this fixture, so the
margin over the 1.5% tolerance is about threefold.

## Sabotage check

`local-runs.json` records the same suite on a MacBook with the committed code
(median 0.31%, mirrored 4.66%, all checks passed) and with the web view's
mirror flipped once (`mirror: !controller.isFrontCamera`, reverted before
committing): the check failed with median 4.67% and the mirrored hypothesis
at 0.32%, naming the cause.

## What this does not prove

- The deployed site. `verify-deployment` runs `cameraChecks()`, so this check,
  against GitHub Pages, but deployment runs only for pushes to `main` or
  `feat/web-face-landmarker`; on this pull request both deploy jobs were
  skipped. The first deployed-URL result comes with the next deploy.
- A physical webcam. The CI camera is a file-backed fake device; the
  MacBook sessions in `2026-09-18-web-face-landmarker` predate this check.
- The GPU delegate, other viewports and other browsers. The check runs on the
  CPU delegate at 1280x720 in Chromium; the later GPU switch and the 390 and
  1440 px viewports check inference and aspect ratio only.

## Files

- `report.json`: the suite's own record from the CI run.
- `local-runs.json`: the MacBook runs, as committed and sabotaged.
- `label-swap.json`, `label_swap_probe.mjs`: the labelling probe and its
  output.
- `sha256.json`: digests of the files above.
