# CPU and Metal comparison

From the vision package root:

```sh
dart build cli -t bin/benchmark_delegates.dart
build/cli/macos_arm64/bundle/bin/benchmark_delegates 120
```

The AOT executable replays the existing portrait as 1920×1080 padded BGRA pixels
through the public VIDEO API. Each task gets 20 warm-up frames followed by 120
measured frames. A second round reverses delegate order. Every frame must return
one face. The input is enlarged with nearest-neighbour sampling and black side
bars; no camera is accessed. Face Landmarker uses one face with tracking and
smoothing, without optional blendshapes or matrices, matching the camera demo.

Latency includes the image snapshot, worker transfer, BGRA conversion, native
inference and result copying. It excludes capture, preview rendering and startup.
JSON output also reports task creation time; first-use and subsequent startup
times differ substantially due to process initialization and shader caches.

Measured on Apple M4 Max, macOS arm64, Dart 3.12.2, on 2026-09-12, using the
`face-detector-v1.0.0-2` and `face-landmarker-v1.0.0-2` native libraries:

| Task | Delegate | Mean ms, rounds 1 / 2 | p95 ms, rounds 1 / 2 |
| --- | --- | --- | --- |
| Face Detector | CPU | 5.36 / 5.24 | 5.92 / 5.59 |
| Face Detector | Metal | 6.47 / 6.07 | 7.12 / 6.47 |
| Face Landmarker | CPU | 9.05 / 8.79 | 9.79 / 9.14 |
| Face Landmarker | Metal | 8.29 / 8.29 | 9.00 / 8.96 |

Metal was slightly faster for the tracked mesh and slower for the small detector
in this workload. CPU remains the default. These are fixture replay timings on
one Mac, not live-camera FPS, accuracy measurements, or a guarantee for other
hardware. The pixel-copy interface still incurs CPU work with either delegate;
GPU selection does not introduce a zero-copy camera path.
