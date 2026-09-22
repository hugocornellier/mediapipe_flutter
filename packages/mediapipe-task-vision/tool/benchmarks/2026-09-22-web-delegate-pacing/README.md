# Web Face Landmarker: CPU vs GPU at camera cadence, 2026-09-22

Question: why does Google's web demo show GPU slower than CPU on this M4 Max
(about 12-13 ms vs 10-11 ms, matching the gallery's native 11.9 vs 10.8),
when a Google engineer saw GPU 5 ms and CPU 10 ms on the same demo on his own
M4 Max?

Machine: MacBook Pro, Apple M4 Max, AC power, High Power mode, Chrome
153.0.8010.52, WebGL renderer `ANGLE (Apple, ANGLE Metal Renderer: Apple M4 Max)`.

## Method

`index.html` runs Google's `@mediapipe/tasks-vision` 1.0.1 FaceLandmarker in
a module worker with the demo's exact task options (VIDEO mode, one face,
0.5 confidences, fresh WASM instance per task, no CPU fallback) and the
demo's model (`float16/1`, SHA-256 `64184e22…`, identical to the gallery's).
It times what the demo times: `performance.now()` around `detectForVideo()`
only. Input is a fixed 60-frame 640x480 clip of `landmark-ex1.jpg` with a
small head motion, as GPU-backed `ImageBitmap`s like the demo's
`createImageBitmap(video)`.

Each condition runs CPU, GPU, GPU, CPU blocks of 60 warm-up and 300 timed
calls. "Back to back" starts each call when the last returns; "16.7 ms" and
"33.3 ms" start calls on a 60 or 30 fps schedule, as a camera would. `load`
adds background work during the run: `gpu[:n]` animates a small WebGL canvas,
`cpu[:n]` spins n busy workers. Timer resolution is 0.1 ms (Chrome coarsens
`performance.now()` without cross-origin isolation). `run.mjs` drives the
installed Chrome headed; every run below kept the tab visible and found the
face in all timed frames. Raw samples are in `results/`.

## Results

Median ms per `detectForVideo`, demo outputs (blendshapes and matrices),
nothing else running. Two runs where repeated.

| Call spacing | CPU | GPU |
| --- | --- | --- |
| Back to back | 8.2 | **5.0** |
| 16.7 ms (60 fps) | 9.5, 9.3 | 11.3, 10.9 |
| 33.3 ms (30 fps) | 11.8, 12.0 | 9.8, 11.1 |

Landmarks only (no blendshapes or matrices) behaves the same: 8.1 / 5.2 back
to back, 9.4 / 10.4 at 16.7 ms, 11.7 / 12.0 at 33.3 ms.

With background work, at 33.3 ms spacing (16.7 ms in brackets):

| Load | CPU | GPU |
| --- | --- | --- |
| none | 11.8, 12.0 (9.5, 9.3) | 9.8, 11.1 (11.3, 10.9) |
| `gpu` (light WebGL canvas) | 11.3 (9.0) | 11.8 (10.7) |
| `gpu:1024` | 11.5 (9.4) | 10.8 (9.9) |
| `cpu:1` (one busy thread) | 8.8, 9.2 (8.8, 8.8) | 7.4, 9.6 (9.8, 9.9) |
| `cpu:4` | 9.3 (9.1) | 10.3 (9.9) |
| `cpu:2,gpu:1024` | 9.2 (9.1) | 9.8 (9.0) |

Spaced GPU is erratic: its block medians range from 7.0 to 12.5 ms across
these runs, while CPU blocks agree to within 0.4 ms.

A separate probe (Chrome's fake camera at 10 fps, display at 120 Hz) saw
`video.currentTime` change 10 times per second, once per camera frame. The
demo only submits a frame when `currentTime` changes, so its call rate is the
camera's frame rate, not the display's.

## What this shows

1. Kept busy, the GPU delegate is clearly faster: 5.0 vs 8.2 ms. That is the
   engineer's 5 ms.
2. At camera cadence on an otherwise idle Mac, both delegates slow down and
   the GPU loses its lead, landing between 9.8 and 12 ms against the CPU's
   9.3 to 12. That is this machine's demo reading and the gallery's native one.
3. Most of the slowdown is the machine idling between frames. One busy
   background CPU thread brings the CPU delegate at 30 fps from about 12 ms to
   about 9, and sometimes lets the GPU reach 7 ms, but nothing tried brought
   spaced GPU back to 5 ms. Extra GPU rendering alone did not help.

It does not show what made the engineer's GPU run at its back-to-back speed.
Consistent with this data: other work keeping his machine awake between
frames (for example the video call he was on), or a momentary reading, since
the demo displays only the latest frame's time. Running this page on his
machine settles it.

## Running it

From a checkout, with Google Chrome installed and `npm ci` done in
`gallery/tool/browser`:

```sh
node packages/mediapipe-task-vision/tool/benchmarks/2026-09-22-web-delegate-pacing/run.mjs
node packages/mediapipe-task-vision/tool/benchmarks/2026-09-22-web-delegate-pacing/run.mjs --outputs=demo --load=cpu:1
```

Without a checkout: save `index.html`, serve its folder
(`python3 -m http.server`), open `http://localhost:8000/index.html` in
Chrome, press Run, keep the tab visible for about four minutes, and send back
the JSON. The library and model load from their public URLs, and the portrait
from this repository on GitHub.
