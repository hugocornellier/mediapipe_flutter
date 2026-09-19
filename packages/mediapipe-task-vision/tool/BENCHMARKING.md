# CPU and Metal comparison

The [2026-09-12 packing experiment](benchmarks/2026-09-12-bgra/README.md)
retains an ABBA comparison, raw timing logs, and a measured BGRA optimization.

## Face pipeline profiling

Build an AOT executable and run from the vision package root:

```sh
dart build cli -t bin/benchmark_face_pipeline.dart -o build/benchmarks/baseline
build/benchmarks/baseline/bundle/bin/benchmark_face_pipeline build/benchmarks/baseline-a
```

Optional positional arguments after the output prefix set measured frames and
rounds (defaults: 150 and 3). Each case warms up for 30 frames. The seeded case
order reverses on alternating rounds. Stop camera capture and avoid concurrent
builds, tests, or GPU workloads during measurement.

The harness measures the full public API and, separately, an instrumented
synchronous native wrapper on its own isolate. Public samples split the owned
pixel snapshot from the request round trip (worker delivery, preparation, the
official task, and returning results). Native samples split packing/conversion,
C image creation, options setup, task execution, result copying, and cleanup.
The task stage includes the whole official graph and synchronization, not just
neural-network execution. Do not subtract percentiles from the two experiments
to infer isolate overhead. Production calls do not enable native instrumentation.

Inputs are the same aspect-preserving portrait replay at 640×480, 1280×720,
and 1920×1080, with BGRA and 64 bytes of row padding. A 1080p RGBA control measures
the path without channel swapping. Both delegates use VIDEO mode, one face,
33 ms timestamps, no pacing, and no optional blendshapes/matrices. Every frame
must return 478 finite landmarks, the matching timestamp, and no optional outputs.
This is steady tracked-face throughput; it excludes real camera delivery,
rendering, face reacquisition, and multi-face costs. Run the official-reference
tests separately to verify numeric correctness, not just landmark counts.

Each invocation writes compressed raw per-frame timings (`.json.gz`) and readable
statistics (`.summary.json`), including mean, p50/p95/p99, min/max and standard
deviation. Metadata records model/fixture/native-library/executable SHA-256,
Dart/OS/hardware, Git state at run time, and thermal reports. Git state at run
time does not identify the source of an older retained executable: record its
build commit alongside the executable hash when comparing revisions.

Keep baseline and candidate AOT bundles. Run baseline, candidate, candidate,
baseline (ABBA) and compare repeated results and the unchanged RGBA control to
detect drift. Never run the variants simultaneously. Raw native stderr should
also be retained when automating runs to verify Metal initialization.

Compare retained run prefixes with the standard-library-only Python tool:

```sh
python3 tool/compare_face_benchmarks.py --baseline build/benchmarks/baseline-a build/benchmarks/baseline-d --candidate build/benchmarks/word-swap-b build/benchmarks/word-swap-c --output build/benchmarks/comparison
```

It checks raw-log hashes, sample counts, matching environments, case coverage,
and model/native-library identity. Each variant must use one executable hash.
The output includes equally weighted round means, their ranges, and pooled
percentiles. Frames within a run are correlated; these are descriptive results,
not statistical confidence intervals or performance guarantees.

## Original combined detector/landmarker benchmark

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

Metal was slightly faster for tracked facial landmarks and slower for the small detector
in this workload. CPU remains the default. These are fixture replay timings on
one Mac, not live-camera FPS, accuracy measurements, or a guarantee for other
hardware. The pixel-copy interface still incurs CPU work with either delegate;
GPU selection does not introduce a zero-copy camera path.
