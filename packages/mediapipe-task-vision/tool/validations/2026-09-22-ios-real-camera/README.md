# iOS arm64 real camera validation, 2026-09-22

iPhone 15 Pro (A17 Pro), iOS 27.0, built from a Mac with Xcode 27.0 and Flutter
3.44.8. `gallery/integration_test/real_camera_test.dart` was run with
`flutter test -d <device>` against the gallery prepared with
`--target ios/arm64 --tasks face_landmarker`, which selects Google's
official MediaPipe Tasks 1.0.1 iOS SDK. The maintainer held the phone facing
himself for the run. The test passed twice in a row; this is the second run.

- Cameras enumerated: four built-in devices, all sensor orientation 90.
  The front camera was selected and delivered 480x640 BGRA frames
  (portrait-shaped), so the upright rotation was 0.
- First session: 116 processed frames, 2 skipped, face found across
  the counted frames, 478 landmarks, 4.6 ms mean CPU inference,
  4.8 ms per frame end to end.
- Stop, then restart: 29 processed frames, face found, 9.2 ms mean
  inference. Capture was released and reacquired.
- Overlay-alignment oracle, from a native `integration_test` screenshot of the
  preview with the overlay hidden: the official IMAGE task found one face in
  the 1179x1572 preview crop; median deviation 0.0015 of the
  preview diagonal, maximum 0.0025; the mirrored hypothesis scores
  0.0512. Mirror False, rotation 0: the `camera_geometry.dart`
  rule that iOS mirrors preview and stream buffers together, so the overlay
  must not flip, is confirmed against on-screen pixels rather than inherited.
- No errors and no widget exceptions.

`report.json` is the test's own record. No screenshot pixels are retained.
