# Linux x64 real V4L2 camera validation, 2026-09-21

[Passing hosted run 35650306522](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/35650306522)
on `ubuntu-24.04` for commit `22d7c80`, workflow `.github/workflows/linux-camera.yaml`,
test `gallery/integration_test/real_camera_test.dart`.

The camera is a genuine V4L2 device: upstream v4l2loopback built against the
runner's `6.17.0-1022-azure` kernel, with ffmpeg streaming the licensed
`landmark-ex1.jpg` portrait into `/dev/video10` at 640x480, 15 fps. Nothing in
the app is replaced: `camera_desktop`'s GStreamer capture enumerated
`MediaPipe_Fixture (/dev/video10)`, the gallery's live controller, frame conversion,
worker isolate, Google's official CPU Face Landmarker and the GTK preview all
ran as shipped under Xvfb. The hosted runner allows only root to open the node
whatever its mode bits, so the producer and the app ran as root.

- First session: 24 processed frames,
  12 counted with a face, 478 landmarks,
  16.7 ms mean CPU inference.
- Stop, then restart: 19 processed frames,
  12 with a face, 12.6 ms.
- Overlay-alignment oracle: the Flutter view was located on the X screen at
  [0, 0, 1280, 720]; the preview with the overlay hidden was screenshotted, the
  official IMAGE task run over those pixels, and its face compared with where
  the overlay projects the live result. Median deviation 0.0024 of the
  preview diagonal, maximum 0.0194 (chin), mirrored hypothesis
  0.0804. Rotation 0, mirror False: the
  `camera_geometry.dart` rules for Linux match what the plugin really does.
- Zero widget exceptions. The first run of this test had caught
  `CameraPreview` rebuilding on a disposed controller during release; the
  controller now detaches the camera and notifies before disposing it.

`report.json` is the test's own record. No screenshot pixels are retained here;
the run's `linux-real-camera-evidence` artifact holds the raw RGBA preview.
