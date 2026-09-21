# macOS arm64 real camera validation, 2026-09-21

Developer MacBook Pro (Apple Silicon), macOS 27.0, Xcode 27.0, Flutter 3.44.8,
`gallery/integration_test/real_camera_test.dart` run with
`flutter test -d macos` against the gallery prepared with
`--target macos/arm64 --tasks face_landmarker`, which selects Google's
official 1.0.0 macOS landmark runtime. A person sat in front of the built-in
camera for the run.

- Camera: `MacBook Pro Camera`, 1920x1080 BGRA frames through `camera_desktop`, no rotation.
- First session: 386 processed frames, none skipped,
  face found across the counted frames, 478 landmarks,
  6.7 ms mean CPU inference and
  7.7 ms per frame end to end.
- Stop, then restart: 38 processed frames, face found,
  8.4 ms mean inference. Capture was released and reacquired.
- No errors and no widget exceptions.

The overlay-alignment oracle does not run on macOS because `integration_test`
has no screenshot transport for desktop macOS; alignment there remains a
visual check on the Live Face Landmarker page.

Two environment facts surfaced by this run and fixed in the same change:
Xcode 27 rejects the Flutter template's 10.15 deployment target (the gallery
now declares 14.0, the runtime's minimum), and a sandboxed macOS app cannot
write outside its container, so the test prints its record and falls back to
the container's temporary directory. Camera device identifiers were removed
from the retained report.
