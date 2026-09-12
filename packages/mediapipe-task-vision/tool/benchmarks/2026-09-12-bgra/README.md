# BGRA packing experiment — Apple M4 Max

The first pipeline profile identified full-frame BGRA packing as an avoidable
cost. The candidate replaces four byte loads/stores per pixel with a 32-bit
load, bit permutation, and store on aligned little-endian buffers. It preserves
every channel, including alpha. Odd strides and unaligned views keep the
byte-wise implementation. Both face tasks share the conversion helper; this
experiment measures Face Landmarker.

## Results

For 1080p padded BGRA through the public API:

| Delegate | Baseline mean / p95 | Candidate mean / p95 | Mean reduction |
| --- | ---: | ---: | ---: |
| Metal | 8.330 / 9.205 ms | 6.525 / 7.446 ms | 21.7% |
| CPU | 9.381 / 10.483 ms | 7.706 / 8.693 ms | 17.8% |

Native packing fell from 3.344 to 1.772 ms for GPU and 3.353 to 1.818 ms for
CPU (about 46–47%). The change benefits both delegates because input packing
runs on the CPU in either case. The unmodified RGBA control changed by only
1.8% (GPU) / 4.0% (CPU) in aggregate public mean latency.

There was measurable drift: baseline A → D rose from 8.802 to 9.959 ms on CPU
and 8.115 to 8.546 ms on GPU; the RGBA controls also rose. The precise aggregate
percentage therefore should not be attributed entirely to the code change.
However, both candidate runs beat both baseline runs at 1080p BGRA. The native
packing round-mean ranges are disjoint: GPU baseline 3.101–3.663 vs candidate
1.741–1.829 ms, CPU baseline 3.117–3.661 vs candidate 1.749–1.928 ms.
The lower packing cost is repeatable despite the drift.

Validation after the conversion change: 103 vision tests and four camera tests
passed, including official CPU/GPU numerical references and delegate switching.
The new conversion test checks 324 combinations of width, height, padding and
buffer offset against independently constructed RGBA bytes, including arbitrary
alpha values and unchanged source/guard bytes. Analyzer checks passed.

## Revisions and provenance

- Baseline build: `76eb52077dfb469ab2f7fcb3df657e0fb9046517`.
  Executable SHA-256:
  `c956f4ae07952e185b4196c3299e744d910c5faf19dd1c0048d20cfb2e69169b`.
- Candidate build: `eeebfa25548c38da8be3913b9a0831c823cd1e6b`.
  Executable SHA-256:
  `5369632dce56a09365b331f9acf418db2f58749ff57f4a8f54af919dcb7959cf`.
- macOS 26.4 (25E246), Apple M4 Max, 48 GiB RAM, Dart 3.12.2 AOT.
- Both retained bundles contain byte-identical native libraries, verified by
  the comparator. Bundle install-name/signature processing changes dylib hashes
  relative to the published archives; the actual bundled hashes are logged.
- Official Face Landmarker model SHA-256:
  `64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff`.
  No native source, task graph, model, threshold, or output tolerance changed.

The retained executables were run in order **A (baseline), B (candidate),
C (candidate), D (baseline)**. An executable's build revision is the mapping
above; `git_head_at_run` in the logs records the working checkout at invocation,
which differs for C and D. No rebuild occurred between a variant's two runs.

## Method and retained data

Each invocation has 16 cases: four input configurations × two delegates × two
measurement paths. Each case has three rounds, 30 warm-up frames and 150 measured
frames per round. This produces **28,800 measured frames**, plus 5,760 warm-up
frames, across the four invocations. A fixed shuffled order reverses on alternate
rounds. Cases run sequentially, with a fresh persistent task per case/round.

The public path measures owned pixel snapshot and the full worker round trip.
The separate native path measures packing, image creation, task execution,
result copying, and cleanup. Every frame must return one face with 478 finite
landmarks and the correct timestamp. Optional outputs stay off. The camera app
was closed, and builds/tests were kept outside timed runs.

See [comparison.md](comparison.md) for the public latency table and
[comparison.json](comparison.json) for every stage, per-round means and pooled
percentiles. Each run retains `.json.gz` raw microsecond samples, a readable
`.summary.json`, and native stderr. Raw checksums are stored in the summaries.
The native logs confirm the official Metal delegate was created.

Recompute from the vision package root:

```sh
python3 tool/compare_face_benchmarks.py --baseline tool/benchmarks/2026-09-12-bgra/baseline-a tool/benchmarks/2026-09-12-bgra/baseline-d --candidate tool/benchmarks/2026-09-12-bgra/word-swap-b tool/benchmarks/2026-09-12-bgra/word-swap-c --output build/benchmarks/recomputed
```

## Limits

This is a static, aspect-preserving portrait replay with stable tracking,
synthetic increasing timestamps, and **no frame pacing**. The 1080p RGBA case
is a control for code paths that do not swap channels. Capture, preview drawing,
face reacquisition, multiple faces and optional expression/transform outputs
are excluded. These measurements do not establish live-camera latency or the
model's minimum possible execution time. A paced camera workload can have
different scheduling, power-state and memory behavior.

The native task stage includes official preprocessing, inference,
postprocessing, graph scheduling, and CPU/GPU synchronization. It is not a
GPU-kernel timer. Public and native experiments are separate; their percentile
differences are not an estimate of isolate overhead. Pooled percentiles and
round ranges describe this run; they are not confidence intervals over
independent samples.
