# Android emulator webcam passthrough probe, 2026-09-22

A negative result, retained so nobody repeats it: on hosted `ubuntu-24.04`
runners, an x86_64 Android emulator does not expose a passed-through V4L2
webcam to the guest. The planned emulator real-camera job (Android "Face in
view" and "Alignment oracle" cells) cannot be built this way.

[Probe run 35723997790](https://github.com/hugocornellier/mediapipe_flutter/actions/runs/35723997790)
at `8fdbe96` of the `ci/android-camera` iteration branch, since deleted
without merging. The branch's real-camera job failed in all four of its runs
(35720083551, 35721304289, 35722852774, 35723997750); the probe was added to
find out why.

Setup, identical in every job:

- Host camera: upstream v4l2loopback as `/dev/video10`, labelled
  `MediaPipe_Fixture`, `exclusive_caps=1`, opened to `runner` with
  `udevadm settle`, `chmod 666` and an ACL, fed by ffmpeg with the licensed `landmark-ex1.jpg`
  portrait at 640x480, 15 fps, `yuv420p`.
- Emulator 37.1.11.0 (build 15917651), KVM enabled, AVD config
  `hw.camera.front=webcam0` and `hw.camera.back=none`, launched by
  `reactivecircus/android-emulator-runner@v2` with
  `-camera-front webcam0 -camera-back none -debug camera -no-window -gpu swiftshader_indirect -no-snapshot -noaudio -no-boot-anim`.

What the host saw: `emulator -webcam-list` reported
`Camera 'MediaPipe_Fixture' can be specified by label as 'webcam0' or by id as '/dev/video10' and will use pixel format 'YU12'`.

What the guest saw, polled three times 10 s apart after boot:

| System image (x86_64) | `dumpsys media.camera` | `CameraProviderManager` |
| --- | --- | --- |
| API 30 `google_apis` | Number of camera devices: 0 | legacy/0 and internal/0 ready with 0 camera devices |
| API 33 `google_apis` | Number of camera devices: 0 | legacy/0 and internal/0 ready with 0 camera devices |
| API 34 `google_apis` | Number of camera devices: 0 | internal/0 and internal/1 ready with 0 camera devices |
| API 35 `google_apis` | Number of camera devices: 0 | internal/0 and internal/1 ready with 0 camera devices |

Untried alternatives, if the emulator route is revisited: the emulator's
`virtualscene` camera with a poster image (the face would be small and seen
at an angle), or a self-hosted runner with a physical webcam. Until then the
Android face cells need a physical device with a person in view.
