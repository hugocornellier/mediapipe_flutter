# iOS face image-storage benchmark

`ios_face_benchmark.dart` replays the same decoded portrait through the actual
public `FaceLandmarker` API in VIDEO mode, with one face and optional outputs
disabled. Both CPU and Metal are tested at 480×640 and 1080×1920, with padded
BGRA rows, either without pacing or with a target 33 ms frame interval. The
public timing includes the owned Dart pixel snapshot, worker message round
trip, image creation, SDK pipeline, result copying and cleanup. It excludes
frame-pacing waits, validation, model initialization and fixture preparation.
Capture and preview drawing are excluded, so this does not measure complete
camera-to-screen latency.

For each case and launch, twenty warm-up frames precede sixty measured frames
in each of three rounds. A fixed shuffled case order is reversed on alternate
rounds. Every frame must produce one face with 478 finite landmarks, the
correct dimensions and timestamp, and no optional outputs. The first measured
frame's coordinates in each round are retained for same-delegate comparisons
across baseline and candidate apps. CPU and GPU are not compared numerically
to each other.

Four release apps select independent candidates with a benchmark Dart define:

| `MEDIAPIPE_IOS_IMAGE_STORAGE` | Implementation |
| ---: | --- |
| 0 | Original frame-by-frame FFI and Core Video allocation |
| 1 | Task-owned reusable native staging buffer |
| 2 | Task-owned Core Video pixel-buffer pool |
| 3 | Both candidates |

The initial baseline app is built before changing the implementation. Retain
each signed `Runner.app` under `build/codex-tmp/ios-face-benchmark/apps/<mode>/`
with a `receipt.json` mapping source and bundled binary paths to SHA-256
hashes. Build all apps before starting measurements:

```sh
flutter build ios --release -t tool/ios_face_benchmark.dart \
  --dart-define=MEDIAPIPE_IOS_IMAGE_STORAGE=0
# Retain this app, then build and retain modes 1, 2 and 3.
```

The mode overrides are internal benchmark controls. The production default
is mode 2: pooling reduced image creation time and improved unpaced 1080p
throughput in the recorded iPhone A/B runs. Staging reuse is experimental and
requires an explicit override. Keep model, thresholds,
image dimensions, optional outputs and SDK archives identical across modes.

From the repository root, run:

```sh
python3 gallery/tool/run_ios_face_benchmarks.py \
  --device <device-id> \
  --apps build/codex-tmp/ios-face-benchmark/apps \
  --output build/codex-tmp/ios-face-benchmark/campaign
python3 gallery/tool/compare_ios_face_benchmarks.py \
  build/codex-tmp/ios-face-benchmark/campaign
```

The phone must be unlocked for launch. `--mediapipe-benchmark` keeps the screen
awake and enables a benchmark-only device-info channel in the gallery's iOS
app delegate. Normal gallery launches do not enable that channel or change the
idle timer. Every case records thermal state and Low Power Mode; the runner
rejects a campaign with either thermal throttling reported or Low Power Mode
enabled. It also stops if model, photo or decoded-pixel hashes change across
launches. Flutter's JPEG rendering produced different pixel hashes in a few
launches during this campaign; those comparisons were rejected and repeated.
Nominal thermal state does not guarantee constant CPU/GPU clocks.

Two unchanged A/A launches establish replay variability. Each candidate then
uses an independent A/B/B/A block with the retained original baseline on both
sides. The comparator requires matching hashes for model/photo/decoded pixels,
complete samples, identical coverage and same-delegate landmark differences no
larger than 0.0001. This equivalence threshold validates a storage-only change;
it is unrelated to CPU-versus-GPU accuracy tolerances.

An improvement must exceed the larger of 3% and the observed A/A variability
for that case/stage. Both candidate launch means must also beat both baseline
launch means. Other results are marked inconclusive unless a similarly clear
regression occurs. Launch ranges and pooled p50/p95 are descriptive; correlated
frames are not treated as independent experiments for confidence intervals.
The A/A controls reuse one artifact and do not measure independent-build layout
variability. Two candidate launches provide limited evidence across device
states; results should be scoped to this device and workload.

If charging conditions change during the first candidate block, repeat that
entire block under the new conditions using the same retained artifacts:

```sh
python3 gallery/tool/run_ios_face_benchmarks.py \
  --device <device-id> --apps build/codex-tmp/ios-face-benchmark/apps \
  --output build/codex-tmp/ios-face-benchmark/staging-unplugged \
  --schedule 0,1,1,0 --cooldown 30
python3 gallery/tool/compare_ios_face_benchmarks.py \
  build/codex-tmp/ios-face-benchmark/campaign \
  --staging-repeat build/codex-tmp/ios-face-benchmark/staging-unplugged
```

This replaces the staging comparison with the unplugged repeat and selects
consecutive unplugged baseline launches 9 and 10 for A/A controls. It assumes
the phone was unplugged before main campaign index 6. Selected report paths
are recorded in the comparison JSON; superseded data is retained. Default
cooling time between launches is 45 seconds. A stopped campaign can resume
with `--resume` after quarantining a rejected report; saved hashes and artifact
receipts must still match.

Separate `native_profile` cases run on a worker isolate without public message
round trips or pacing. They record image creation, setup, task execution,
result copying and cleanup. These are wall-clock wrapper stages. The task
stage includes Google's preprocessing, scheduling, inference/postprocessing
and the adapter's Objective-C-to-C result conversion. It is not a GPU kernel
timer. Public/native timings come from separate runs and cannot be subtracted
to estimate isolate overhead.

Raw JSON reports and complete console logs are retained alongside a campaign
manifest containing binary/source receipts and report checksums. The console
logs must confirm Metal initialization. The runner never rebuilds during the
campaign and refuses to overwrite reports. Restore the ordinary gallery with
`flutter build ios --release` and reinstall it after testing.
