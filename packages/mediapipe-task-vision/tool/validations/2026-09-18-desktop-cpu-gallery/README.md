Windows x64 and Linux x64 CPU validation passed on 2026-09-18 using Google's
official MediaPipe 1.0.0 wheel libraries, without a Python runtime in the app.

[GitHub Actions run 35358366302](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/35358366302)
tested commit `1197b103b69ca5237a26eabf49fd4df94d9a95b9` on standard
`windows-2025` and `ubuntu-24.04` hosted runners. Both jobs passed.

The actual gallery checks cover native camera plugin registration and device
enumeration, catalog assets, Face/Hand/Pose VIDEO task coexistence in one
process, and release builds containing one original official runtime library.
The Face Landmarker page processes supplied portrait frames through its real shared
controller, conversion, isolate worker and native CPU task. It produces 478
finite landmarks and checks padded RGBA/BGRA color equivalence using the first
frame of each fresh VIDEO task, camera switching, stop/start and cleanup.

Hosted CI has no physical webcam. The capture interface supplies frames during
the gallery test. Native webcam opening, permissions, actual captured pixel
formats, preview mirroring and visual landmark alignment remain unverified on
Windows and Linux hardware. No desktop GPU support is claimed.

The existing package CPU suite also passed its native tests, same-host official
Python reference checks, and debug/release consumers on both platforms.
Native `report.json` files retain comparison diagnostics against checked-in
references, including expected numerical differences; a successful run does
not imply every checked-in value is bit-identical across platforms.

`receipt.json` identifies the run, jobs, downloaded artifact hashes and exact
tested source hashes. Per-platform folders retain gallery logs/reports and
selected native logs/reports/provenance. `sha256.json` hashes the retained files.
The gallery README includes target preparation and physical-camera smoke
commands. Use the ordinary Live Face Landmarker page to check visual alignment.

The retained receipt and source hashes tie these results to the exact tested CI
snapshot.
