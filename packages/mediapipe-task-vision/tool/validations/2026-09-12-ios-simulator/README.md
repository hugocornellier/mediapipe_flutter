# iOS simulator CPU validation — 2026-09-12

The official Face Detector and Face Landmarker ran successfully inside Flutter
on an **iPhone 17 Pro simulator, iOS 26.4**, hosted on an Apple M4 Max Mac.
The final run used clean source commit
`85b71fa9b8e4894bebc5dd18eaea7989d1b3722b`, Flutter 3.44.8 / Dart 3.12.2,
and Xcode 26.6 (17F113). The native SDK reports 26.5.

## Results

| Check | Result |
| --- | --- |
| Flutter iOS CPU integration | 8 tests passed |
| macOS vision CPU/Metal regressions | 107 tests passed |
| macOS camera-controller/example tests | 4 tests passed |
| Vision package analyzer, including the example | No issues |
| Changed Dart source formatting | No changes needed |
| MediaPipe and OpenCV source diffs | Both empty |

[The simulator log](flutter-test.log) and [machine-readable report](report.json)
record the final integration run, source commit, empty Git status, exact device,
command, and complete native manifests. The [macOS regression log](macos-regression.log)
was captured earlier during the same implementation session, before the final
deployment-metadata and documentation corrections.

The integration tests preserve the existing official CPU reference tolerances:
detector boxes within 1 pixel, scores/keypoints within `1e-5`; landmark coordinates
within `1e-4`, blendshapes within `0.002`, and transform entries within `0.005`.
No models, task graphs, reference values or tolerance limits were changed.
Coverage includes IMAGE/VIDEO, two faces, rotations, padded pixel formats,
tracking/loss/re-entry, errors, concurrent task libraries and queued disposal.
Explicit GPU rejection is tested alongside successful subsequent CPU creation.

The interactive image app also launched successfully and displayed the full
478 facial landmarks, irises and 52 expression scores on bundled portraits. The UI
uses the same public APIs exercised by the integration tests.

## Native provenance

Both binaries are CPU-only, ARM64, `IOSSIMULATOR`, with a Mach-O minimum of iOS
14.0. The build requests 13.0, which Apple clang floors to 14.0 when linking for
the ARM64 simulator. Only system-library dependencies are present. The builder
checks all required C exports, architecture, platform and binary hashes.

| Runtime | Bytes | SHA-256 |
| --- | ---: | --- |
| Face Detector | 10,981,208 | `5a2204ec2648fa3f5612e1fd404282eb55349d56559e585f4e54a04c4103791d` |
| Face Landmarker | 13,181,112 | `e702db8bffecf22d0fd76860bb296cf9a0649436224a579a422b3e5f849d197b` |

MediaPipe v1.0.0: `6d31f1ebc3284db74d211d62bdc4f0a0c29ea120`.
OpenCV 4.12.0: `49486f61fb25722cbcf586b7f4320921d46fb38e`.
Both upstream checkouts were verified unchanged after building.

## Reproduce and interpret

Follow [the simulator guide](../../IOS_SIMULATOR.md), then run from the vision
package:

```sh
python3 -B tool/test_ios_simulator.py --device <installed-simulator-uuid>
```

These are local development libraries; simulator release archives have not been
published. The app runs in Flutter debug mode with optimized native C++. This
establishes functional simulator CPU inference, not physical iPhone support,
GPU support, live-camera support, compatibility with older simulator runtimes,
or device performance. Hosted macOS GPU numerical differences documented in
the parent Metal PR remain a separate issue; local passes do not resolve them.
