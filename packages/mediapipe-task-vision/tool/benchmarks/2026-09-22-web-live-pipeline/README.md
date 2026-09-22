# Web live Face Landmarker pipeline, stage by stage, 2026-09-22

Question: where does the gallery's live browser pipeline spend its time, from
a camera frame reaching the page to its landmarks on screen, and which changes
make it measurably faster?

Machine: MacBook Pro, Apple M4 Max, AC power, High Power mode, Chrome
153.0.8010.53, page on the main display (LG UltraFine 6K, 60 Hz). Release web
build of the gallery, official tasks-vision 1.0.1 runtime, CPU and GPU
delegates.

## Method

`run.mjs` drives the installed Chrome headed (real GPU) with Chrome's fake
camera playing a 30 fps 640x480 clip of `landmark-ex1.jpg` drifting on a slow
ellipse. With `?pipeline-trace` in the URL, the gallery records each processed
frame (`gallery/lib/web/pipeline_trace.dart`); the worker reports its own
`detectForVideo` and serialization times through `mediapipeVision.onTiming`.
Every block discards 1000 warm-up frames after the task starts, so clocks and
the runtime settle, then times 1000 frames. Every frame found the face.

Stages per frame, in milliseconds:

| Stage | From, to |
| --- | --- |
| `queue` | frame callback (`requestVideoFrameCallback`) to capture starting |
| `capture` | `createImageBitmap(video)` |
| `inference` | the worker's `detectForVideo` |
| `serialize` | the worker preparing its reply |
| `transport` | the round trip less `inference` and `serialize`: both messages and decoding in Dart |
| `detectDone` | frame callback to the result in Dart |
| `handle` | publishing the result to listeners (added for fix 4) |
| `waitFrame` | result to the start (vsync) of the Flutter frame that paints it |
| `render` | that Flutter frame: build, layout, paint; later runs also include every post-frame callback |
| `present`, `refresh` | end of that frame, and its vsync, to the next browser frame |
| `e2e` | frame callback to the browser frame after the result was painted |

Two sources of error shaped the method:

- **Display refresh.** On the built-in ProMotion display the page switched
  between 60 and 120 Hz with its load, which moved `e2e` by about 8 ms. The
  window now opens on the main display, and `refresh` is recorded per frame.
- **Drift.** The same build's CPU `inference` moved by about 0.3 ms between
  runs an hour apart, enough to fake or hide a saving. Fixes are therefore
  judged by builds compared within one run (`--variants`): per delegate the
  blocks run A, B, B, A, reversed on the next round, each in a fresh page. A fix
  passes when its target stage improves in every adjacent pair and the stages
  it should not touch (the controls, chiefly `inference`) stay put.

`--isolated` serves the page cross-origin isolated, so `performance.now()`
resolves to about 5 us instead of 100 us; all fix comparisons used it.

## Baseline

`results/chrome-baseline-*.json`, before any change, 8 blocks, means:

| Stage | CPU | GPU |
| --- | --- | --- |
| `queue` | 0.18 | 0.18 |
| `capture` | 0.11 | 0.13 |
| `inference` | 9.72 | 9.74 |
| `transport` | 0.31 | 0.36 |
| `waitFrame` | 6.29 | 6.22 |
| `render` | 3.06 | 3.34 |
| `refresh` | 17.01 | 17.07 |
| **`e2e`** | **33.67** | **33.74** |

`e2e` is two 60 Hz display frames in every block (33.63 to 33.78 ms): the
result misses the frame it arrives in and appears one refresh after the next.
Only `detectDone` can change that, by crossing a vsync; `render` happens inside
a refresh, so a faster render frees main-thread time without lowering latency.
Nothing waited for the worker: inference takes about 10 ms of the 33 ms frame
interval, so pipelining capture with inference cannot help at 30 fps and was
not built.

## Fixes

Block means, ranges over the blocks of each variant.

| Fix | Target stage | Before | After | Controls | Verdict |
| --- | --- | --- | --- | --- | --- |
| 1. Overlay lines with one `drawRawPoints(PointMode.lines)` per group instead of four stroked `Path`s (2,688 segments) | `render` | CPU 3.20 to 3.60, GPU 3.87 | CPU 2.55 to 2.58, GPU 3.13 | `inference`, `transport` unchanged | **Kept** |
| 2. Capture with `new VideoFrame(video)` instead of `createImageBitmap` | `capture`, `detectDone` | capture 0.107 to 0.129; CPU detectDone 10.31 | capture 0.011 to 0.012; CPU detectDone 10.60 | CPU `inference` up 0.3 to 0.5 in all 4 pairs | **Rejected** |
| 3. Landmarks sent from the worker as a transferred `Float64Array` instead of JSON | `transport` | CPU 0.300 to 0.320, GPU 0.369 to 0.380 | CPU 0.197 to 0.241, GPU 0.254 to 0.273 | `inference` unchanged; CPU `detectDone` down 0.18, lower in all 4 pairs | **Kept** |
| 4. Per-frame `data-*` attributes and overlay probes only with `?test-hooks` (the browser suite) | `handle`, `render` | handle 0.024 to 0.028 | handle 0.015 to 0.018; render down 0.02 to 0.15 | `inference`, `transport` unchanged | **Kept** (small) |

Evidence:

- Fix 1: `results/chrome-iso-abba-pre1-fix13-fix134-interrupted.txt` (the
  first 9 of 24 blocks; the browser closed during block 10), after the earlier
  sequential runs `chrome-baseline` and `chrome-fix1-rawpoints` (CPU 2.98 to
  3.17 to 2.28 to 2.40, GPU 3.10 to 3.87 to 2.89 to 2.99, every block).
  `results/fix1-overlay-path-vs-rawpoints.jpg` compares the drawing (left:
  `Path`, right: `drawRawPoints`, 3x; the camera moved between shots). Line
  weight, colour and the brighter vertices match, and the browser suite's
  overlay alignment oracle passes.
- Fix 2: `results/chrome-iso-abba-fix1-fix13-fix123-*.json`. The capture
  saving is real, but the camera's YUV frame then reaches MediaPipe's texture
  upload unconverted and inference absorbs the cost, and more. GPU blocks were
  too erratic (7 to 11 ms) to separate, and pooled they lean worse too
  (detectDone 10.57 to 10.92). The change is kept as
  `results/fix2-videoframe-rejected.patch`. A first, sequential comparison
  (`chrome-iso-fix1`, `chrome-iso-fix2-videoframe`) pointed the same way but was
  within drift; the interleaved run settled it.
- Fix 3: the same interleaved run; worker `serialize` also fell from 0.05 to
  0.01 (`chrome-iso-fix3-packed`). Blendshapes and matrices stay JSON; named
  landmarks fall back to JSON. `test/result_test.dart` covers the packed path.
- Fix 4: the interrupted run above. `tool/browser/test_browser.mjs` now loads
  the gallery with `?test-hooks`; its camera suite passes.

Together, fixes 1, 3 and 4 remove about 0.6 to 0.8 ms of main-thread work per
frame on CPU (about a fifth of the gallery's own share) and about 0.1 ms from
`detectDone`. `inference` is Google's runtime and unchanged, and `e2e` stays at
two display frames.

Not measured here: Firefox and Safari. A manual check in both found them
working, with GPU inference readings that vary more than Chrome's, as all
browsers' GPU delegates do between runs.

## Running it

From a checkout, with Google Chrome, ffmpeg, `npm ci` done in
`gallery/tool/browser`, and the gallery prepared (`python3 -B
gallery/tool/prepare.py --target web`):

```sh
(cd gallery && flutter build web --release --base-href /mediapipe_flutter/ --no-web-resources-cdn)
node packages/mediapipe-task-vision/tool/benchmarks/2026-09-22-web-live-pipeline/run.mjs --label=current --isolated
```

To compare builds, copy each `gallery/build/web` aside and pass them:

```sh
node packages/mediapipe-task-vision/tool/benchmarks/2026-09-22-web-live-pipeline/run.mjs --label=compare --isolated \
  --variants=before=build/bench/variants/before,after=build/bench/variants/after
```

A full two-variant run takes about 20 minutes. `results/` keeps per-block
summaries; the per-frame rows were removed to keep the repository small. The
`dirty` flag in some results comes from a tool rewriting
`gallery/analysis_options.yaml` during the session, which web builds do not
read.
