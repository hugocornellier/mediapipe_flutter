# iOS face storage: measured before/after

Keep **Core Video pixel-buffer pooling** for the official iOS face landmarker.
Do not enable reusable FFI staging by default: its public API changes were below
the acceptance threshold in every case. Google’s prebuilt Tasks SDK remains
unchanged; this work only changes the adapter's BGRA image storage.

Release apps ran on Hugo’s iPhone 15 Pro (`iPhone16,1`, A17 Pro), iOS 26.5,
using Google MediaPipe Tasks 1.0.1. The accepted comparisons were unplugged,
with Low Power Mode off and nominal reported thermal state throughout.
Two unchanged launches varied by 0.49–2.49% in public API timing. The acceptance
floor was therefore 3%, also requiring both candidate launches to beat both
bookending baseline launches.

| Candidate | Unpaced 1080p CPU, before → after | Unpaced 1080p GPU, before → after | Decision |
| --- | ---: | ---: | --- |
| Reusable FFI staging | 9.900 → 9.781 ms (1.2%) | 10.861 → 10.782 ms (0.7%) | Inconclusive; disabled by default |
| Core Video pool | 10.033 → 9.504 ms (5.3%) | 10.885 → 10.407 ms (4.4%) | Enable pooling |
| Both | 9.977 → 9.321 ms (6.6%) | 10.899 → 10.293 ms (5.6%) | Faster than baseline; does not establish an additional staging benefit |

Pooling reduced separately profiled native image creation by 44–58% across
both sizes and delegates. Google's SDK task stage did not clearly improve.
All paced public cases and all 480×640 public cases were inconclusive; there
were no accepted public regressions. For the paced 480×640 workload, pooling
was essentially flat: CPU 12.216 → 12.241 ms, GPU 16.831 → 16.840 ms. This
optimization does **not** establish a live-camera latency improvement or make
GPU faster than CPU.

Every measured frame returned one face with 478 finite landmarks. Matched
delegates produced **zero maximum coordinate difference** across all selected
baseline and candidate oracles. Optional outputs were disabled throughout.
See [the full public API table](comparison.md) and [all stage timings,
percentiles, launch means and selected report paths](comparison.json).

The harness replays one static portrait in VIDEO mode, using padded BGRA rows
at 480×640 and 1080×1920. Each public case has three rounds of twenty warm-up
and sixty measured frames. Public timing includes the Dart pixel snapshot,
worker round trip, native image creation, SDK task and result conversion.
Separate native profiles do not include public message round trips or pacing.
Model creation, validation, pacing waits, capture and preview rendering are
excluded. These results are scoped to this device and tracked static scene;
they do not establish results for moving faces, other devices or all delegates.

The first staging block crossed a charging-condition change. A subsequent
repeat had mismatching decoded-pixel hashes from Flutter JPEG rendering.
Both blocks are excluded from the final comparison. The second unplugged
repeat has matching decoded-pixel hashes. One thermal-confounded main run
was also rejected and repeated. Superseded and rejected data is preserved.
See [conditions.json](conditions.json). The consecutive unchanged main launches
9 and 10 provide the unplugged A/A controls and also serve as bookending
baselines; they are not additional independent experiments. Correlated frames
are not treated as independent replicates for confidence intervals.

[raw-results.tar.gz](raw-results.tar.gz) contains raw reports, full console logs
(including Metal initialization), manifests with source/binary receipts,
exact pre-optimization and candidate source snapshots, and the original
benchmark entrypoint. The signed apps remain ignored under
`build/codex-tmp/ios-face-benchmark/apps/{0,1,2,3}/`; builds were finished before
measurements. [sha256.json](sha256.json) records artifact checksums.
[baseline-to-candidates.patch](baseline-to-candidates.patch) records the storage
experiment, before enabling mode 2 as the production default.

After extracting the archive into a workspace scratch directory, reproduce
the comparison from the repository root:

```sh
python3 gallery/tool/compare_ios_face_benchmarks.py <extracted>/campaign \
  --staging-repeat <extracted>/staging-unplugged-verified
```

See [the harness and rerun instructions](../../../../../gallery/tool/IOS_FACE_BENCHMARK.md).
Production selects pool-only mode 2. Modes 0, 1 and 3 remain explicit internal
benchmark overrides; normal gallery builds do not request staging reuse.

The final pool-only default passed a fresh on-device CPU/Metal SDK smoke test:
padded RGB/RGBA/BGRA, rotation, optional outputs, VIDEO timestamps, detector
coexistence, invalid-model recovery and repeated small blank → larger face →
small blank transitions. See [pooled-sdk-smoke.json](pooled-sdk-smoke.json).
Dart/gallery analysis and the four benchmark-comparator tests passed; the
existing face/native-assets suite also passed during this campaign.
The ordinary gallery was rebuilt without benchmark overrides, installed and
launched on the iPhone. Its bundle contains one MediaPipe SDK framework;
[normal-gallery-receipt.json](normal-gallery-receipt.json) records the final
source and bundled binary hashes.
