# Windows x64 real camera validation, 2026-09-22

[Passing hosted run 35721724171](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/35721724171)
on `windows-2025` (Windows Server 2025, build 26100) for commit `ac05023` of
the `ci/windows-camera` iteration branch. Workflow
`.github/workflows/windows-camera.yaml`, test
`gallery/integration_test/real_camera_test.dart`. The camera, host and test
code are identical in `9456524` on `feat/face-landmarker-hardening`; only the
workflow's push trigger (which lost the iteration branch) and the vcam
README's notes differ.

The camera is a genuine Media Foundation capture device. `gallery/tool/windows/vcam`
builds a Frame Server custom media source (adapted from Microsoft's
VirtualCamera sample) that shows the licensed `landmark-ex1.jpg` portrait
letterboxed into 640x480 at 30 fps, registers it under HKLM, and creates it
with `MFCreateVirtualCamera` for the session. Nothing in the app is replaced:
`camera_desktop`'s capture engine enumerated and opened it, and the gallery's
live controller, frame conversion, worker, Google's official CPU Face
Landmarker and the preview ran as shipped.

- The device: "MediaPipe Fixture (Windows Virtual Camera)", a `vcamdevapi`
  software device (`vcam-host.log`). Opened the way `camera_desktop` opens a
  camera, it offered RGB32 and NV12 at 640x480, 30 fps, delivered 60 frames
  in 2.02 s (29.7 fps), and the last frame matched the embedded fixture
  exactly: mean absolute difference 0.00 per channel, against 58.32 if
  mirrored and 44.32 if flipped (`vcam-smoke.log`).
- First session: 37 processed frames, 12 counted with a face, 478 landmarks,
  640x480 frames, rotation 0, 18.6 ms mean CPU inference.
- Stop, then restart: 37 processed frames, 12 with a face, 16.7 ms. Capture
  was released and reacquired.
- Overlay-alignment oracle: the desktop was set to 1920x1080 at 96 DPI; the
  magenta calibration frame placed the Flutter view at (18, 41), 1264x681, one
  screen pixel per logical pixel. The preview with the overlay hidden was
  copied from the desktop, the official IMAGE task found one face in the
  694x521 crop, and median deviation from the overlay's projection was
  0.0031 of the preview diagonal, maximum 0.0145 (chin); the mirrored
  hypothesis scores 0.0465.
- Mirror true, rotation 0. `camera_desktop` 1.2.1 does not flip frames in
  native code on Windows: `buildPreview()` wraps the texture in a Flutter
  `Transform`, and the image stream stays unflipped. So the preview mirrors
  the analysed frame, and `previewIsMirrored` returning true on Windows is
  confirmed against on-screen pixels. Before the oracle compared mirrored
  previews under mirrored landmark labels (see `2026-09-22-web-alignment`),
  this correct overlay would have failed.
- No errors, no widget exceptions. The host was still running after the test.

What it took on the runner (iterations 35719479621, 35720518019):
`IMFVirtualCamera::Start` returned `E_ACCESSDENIED`, which Microsoft
documents as the webcam privacy control; the user-level consent value under
`HKCU\...\CapabilityAccessManager\ConsentStore\webcam` was absent, and setting
it, with the device and desktop-app switches, and restarting `camsvc` and the
Frame Server services made it succeed. A camera host started in one step did
not survive into the next, so the host and the test share one step.

What this does not prove: a physical webcam (driver formats such as MJPG or
YUY2, autofocus, exposure changes), other resolutions, DPI scaling other
than 100%, or Windows on ARM.

`report.json` is the test's own record. The run's
`windows-real-camera-evidence` artifact also holds the raw RGBA preview and a
bitmap of a delivered frame; no pixels are retained here.
