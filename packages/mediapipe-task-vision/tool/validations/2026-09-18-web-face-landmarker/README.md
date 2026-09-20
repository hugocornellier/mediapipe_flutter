# Official web FaceLandmarker validation — 2026-09-18

[Passing hosted workflow](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/35393300772)
for implementation `b3d7c6cbe3000f56fd0fde7a1b35caa68aae6c8e`.
Chrome's 15 release checks cover public Dart inference and browser camera capture;
Firefox's seven checks cover the release API. Both compare all landmark,
blendshape and matrix values with Google's direct official JavaScript API in
the same browser. The maximum absolute error was zero for all three groups.
Full inputs, reference arrays, logs and fixture screenshots are in that run's
`web-face-evidence` artifact.

The CI camera is Chrome's file-backed portrait/blank/portrait webcam, with a
separate two-device browser capture test. Permission denial, missing cameras,
worker error/restart, simulated track-ended events, responsive preview sizing,
mirroring and resource cleanup are exercised. Firefox on GPU-less hosted Linux
uses a virtual display and Mesa software WebGL for official CPU preprocessing.
The lightweight Chromium headless shell is excluded because it rejects camera
capture; full Chromium is used.

`physical-camera-local.json` separately records two actual MacBook Pro camera
sessions, each processing at least 20 CPU frames and returning one face with 478
landmarks. Stop/start checks verified worker shutdown and ended capture tracks.
Device/group identifiers were removed; no physical-camera images are archived.
That check used the earlier camera implementation commit recorded in the receipt;
subsequent changes normalized extra rotations and unified runtime error types.

`runtime-provenance.json` records the official Google Tasks Vision 1.0.1 tarball's
SHA-512 and extracted file SHA-256 digests. `receipt.json` records the unchanged
official model SHA-256 and native regression counts. Web supports CPU/WASM only;
GPU requests are tested as explicit unsupported errors. Safari and mobile
browsers have not been validated. Pages builds record their own source in the
public `build-info.json` and repeat camera checks against the deployed URL.
