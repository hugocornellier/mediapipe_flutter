# Independent face image-storage audit

Audit in progress. The original recorded iPhone comparison reproduces exactly;
the fresh Mac campaign is complete and inconclusive, and fresh iPhone timing
remains pending. Production pooling remains mode
2 and experimental staging remains disabled by default pending the fresh audit.

This continues Claude session `d7584836-a0f1-4d3c-a2a5-4cd3eaefa930` after its
usage limit. Recovered evidence and ongoing reports are retained under
`build/codex-tmp/independent-storage-audit/`. Existing staged and unstaged
implementation changes have been preserved.

## Original evidence

All eight published archive file hashes match `sha256.json`. All four retained
signed artifacts match their recorded App and native bridge hashes. Recorded
source hashes match the archived snapshots, and running the comparator with
the final unplugged staging repeat reproduces `comparison.json` exactly after
removing report paths. The four existing comparator tests pass.

All five fresh iPhone artifacts have native binaries identical to the
corresponding original retained bridge binaries after signature removal.
The baseline uses the original bridge; candidate mode 0 intentionally uses
the same expanded bridge as modes 1-3 while preserving allocation behavior.
All Mac artifacts use one identical native runtime binary.

The original native baseline bridge was rebuilt from the archived baseline and
matches the retained baseline byte-for-byte after removing signatures. The
recompiled Dart App snapshot has a different hash in the isolated source tree.
Its embedded original source URI and private-name identifiers differ, so this
is not a reproducible App binary hash across source locations. This does not
invalidate verification of the original retained binary against its receipt.
The baseline receipt did not record `native_face_landmarker.dart`; its archived
snapshot and patch provide reconstruction evidence rather than an independently
recorded pre-change hash for that file.

The published pool result, 5.3% CPU and 4.4% GPU improvement at unpaced 1080p,
survives a descriptive sensitivity check against all eight eligible unplugged,
canonical-pixel baseline launches: 4.73% CPU and 4.59% GPU, with both pool
launches faster than all eight baselines. This check is not another experiment
and does not supply confidence intervals. Staging remains below the original
acceptance threshold. Paced cases remain inconclusive.

## Limitations found

- The stated 0.49-2.49% variability comes from selected baseline launches 9 and
  10. Broader baseline contrasts are noisier, reaching 3.66% for unpaced 1080p
  CPU and 5.38% for paced 480 GPU. Some of those contrasts are bookends separated
  by candidate launches, so they must not be called consecutive-launch A/A.
- The initial unchanged launches had approximately 1.7-second gaps, while later
  accepted comparisons cooled for roughly 35-55 seconds. The final comparator
  substitutes later controls, which also serve as comparison bookends.
- The device channel recorded battery level but omitted charging state. The
  accepted unplugged condition depends on the recorded operator confirmation.
  Nominal thermal state does not establish constant CPU/GPU clocks.
- All 23 campaign/repeat reports and all 22 live console logs are present in
  the published raw archive and match the live data byte-for-byte, including
  the two reports with different decoded-pixel hashes. The initial standalone
  baseline report is outside the archive. All 24 original reports are now
  retained. Deviant-pixel coordinate differences are about 0.005, so exclusion
  from accepted comparisons is necessary. No campaign reports were omitted.
- Every original frame was checked for face count, finite coordinates, optional
  outputs, dimensions, and timestamps. Cross-artifact coordinate oracles were
  only the first measured frame in each round, rather than every frame.
- The original comparison has one A/B/B/A block per candidate, with two candidate
  launches. It does not establish an incremental benefit of staging over pooling,
  nor a complete live-camera or camera-to-screen latency improvement.

Public timers include the owned Dart pixel snapshot, worker message round trip,
FFI staging copy, native image creation, SDK execution, output conversion and
cleanup. They exclude pacing waits, validation, task/model creation, capture
and preview. Native stage profiles are separate executions. Their task stage
includes SDK preprocessing, scheduling, inference/postprocessing and adapter
Objective-C-to-C conversion. It is wall time, not GPU kernel time. Public and
native measurements cannot be subtracted to estimate worker overhead.

## Fresh experiment

Five release/AOT artifacts per platform use one harness: archived original
baseline, candidate mode 0 (allocation-fidelity control), mode 1 (staging),
production default mode 2 (pool only, with no storage override), and mode 3
(both). All benchmark builds finished before timed launches. Models, default
thresholds, one face, disabled optional outputs, VIDEO timestamps, delegate,
dimensions and padded strides are identical across artifacts.

The fixtures are pre-rendered raw BGRA assets with compiled expected hashes,
at 480x640/stride 1936 and 1080x1920/stride 4336. They replace per-launch JPEG
rendering. Absolute timings need not equal the old decoded fixture timings;
before/after comparisons use exactly matching bytes within this experiment.

Each launch has three rounds of 20 warm-up and 60 measured frames per case.
Public CPU/GPU cases run unpaced and with approximately 33ms pacing at both
sizes. Native stage profiles run in every round, interleaved with public cases.
All measured landmark sequences are digested, with first/last coordinates
retained for inspection. The runner records charging state, thermal state,
Low Power Mode, receipts and report hashes, and preserves rejected attempts.

The schedule comprises two unchanged A/A controls, one baseline/mode-0
fidelity block, and two A/B/B/A blocks for each candidate. There are 30 launches
per platform, with 45 seconds cooling and 5 seconds settling before timings.
Analysis uses launch means as experimental units, pooled p50/p95 descriptively,
and a floor equal to the larger of 3% and every observed consecutive-launch
baseline A/A difference. Both repeated blocks must pass the floor and both
candidate launches in each block must beat both bookends. Individual frames
are not independent trials.

## Completed correctness checks

All five artifacts on both platforms passed untimed CPU/GPU validation. Within
each platform/delegate, IMAGE reference hashes and VIDEO sequences match
exactly across artifacts. Checks cover padded strides (+0, +16, +256), an odd
477x637 crop, repeated dimension changes, face/blank alternation, twelve public
create/detect/dispose cycles, duplicate disposal, detect-after-disposal rejection,
and direct native duplicate close. iPhone lifecycle RSS does not show monotonic
growth across those cycles. This is a bounded lifecycle check, not a proof of
absence of leaks.

The Mac is Mac16,5 (Apple M4 Max), macOS 26.4; the phone is iPhone16,1 (iPhone
15 Pro), iOS 26.5. Every Mac report has `official_ios_runtime=false`. Code also
checks `Platform.isIOS` before the official SDK marker, and constructs reusable
storage only on that path. Mac measurements therefore check regressions;
these iOS storage changes cannot be claimed to accelerate the Mac runtime.

All 30 fresh Mac launches completed on AC power before Android builds began.
Every measured frame sequence matches exactly, with zero landmark delta across
same-delegate artifacts. All timing comparisons are inconclusive: consecutive
baseline variability reaches 17.78-127.34% for the public cases over the full
campaign. These results supply no fresh performance improvement or regression
claim. The raw archive and its per-file checksums retain the complete campaign.

The iPhone was unplugged with nominal
thermal state and Low Power Mode off during validation, then became unavailable
before timed measurements. Fresh phone timing and final gallery restoration are
pending reconnection of the same phone.

The initial Mac A/A public differences are 2.39-14.87%, materially higher than
the selected original iPhone controls. Existing desktop processes were present
(IDEA, WindowServer, Firefox); a host process snapshot is retained. No builds
or other agent-created heavy jobs ran during timing. Nominal thermal state and
AC power do not remove desktop workload or clock variability; the noise floor
and repeated bookends must govern interpretation.
