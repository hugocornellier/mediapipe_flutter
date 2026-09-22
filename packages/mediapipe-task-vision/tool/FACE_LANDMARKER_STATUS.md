# Face Landmarker live-camera status

One table for the question "does Face Landmarker work on a live camera on this
platform, and how do we know". Every cell links to the record that proves it
or says plainly that nothing proves it yet. Update this file in the same
commit as the evidence; the README defers to it.

Columns, in the order a frame travels:

- **Reference**: official IMAGE/VIDEO outputs match Google's own API for the
  same runtime version on the same machine.
- **Lifecycle**: create, queued frames, timestamps, delegate switch, disposal.
- **Injected pipeline**: the real gallery controller, conversion, worker and
  task, with frames supplied through the camera platform interface.
- **Real capture**: the platform's actual camera plugin opened a real device.
- **Face in view**: that real device showed a face and the task found it.
- **Alignment oracle**: the on-screen preview was screenshotted and the
  overlay's projection matched a fresh IMAGE pass over those pixels
  (`gallery/integration_test/support/alignment_oracle.dart`; on web the same
  check in `gallery/tool/browser/test_browser.mjs`).
- **Background / rotate**: capture survives app backgrounding and a device
  rotation mid-session.
- **Soak**: a sustained session without memory growth or thermal failure.

Symbols: ✅ recorded, ⚠️ partial (see note), ❌ nothing recorded, 🧑 needs a
person or a device that hosted CI cannot provide.

| Platform | Reference | Lifecycle | Injected pipeline | Real capture | Face in view | Alignment oracle | Background / rotate | Soak |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Web (Chrome) | ✅ CPU + GPU, zero error [1] | ✅ [1] | ✅ file-backed webcam in CI [1] | ✅ CI fake device and two real MacBook sessions [1][2] | ✅ real MacBook, CPU and GPU [1][2] | ✅ CI on every pull request, fake webcam, CPU: median 0.35%, mirrored 4.6% [11]; the repeat against the deployed site waits for the next deploy from `main` | ⚠️ track-ended and worker restart only [1] | ❌ |
| Web (Firefox) | ✅ CPU [1] | ✅ [1] | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Web (Safari) | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| macOS arm64 | ✅ CPU + Metal [3] | ✅ [3] | ✅ unit + desktop test | ✅ built-in camera, 1080p, stop/restart [9] | ✅ 478 landmarks on a person, 6.7 ms CPU [9] | ⚠️ visually confirmed by the maintainer on 2026-09-21, CPU and Metal, release build [9]; no screenshot transport for an automated oracle on desktop macOS | ❌ | ⚠️ `tool/test_camera_soak.py` exists, no retained run |
| iOS arm64 (device) | ✅ CPU + Metal, iPhone 15 Pro [5] | ✅ [5] | ✅ | ✅ front camera, 480x640, stop/restart [5][10] | ✅ 478 landmarks on a person, 4.6 ms CPU [10] | ✅ native screenshot oracle: median 0.15%, mirrored 5.1% [10] | ❌ | ❌ |
| Android arm64 (device) | ✅ CPU + GPU, Pixel 7 Test Lab [6] | ✅ [6] | ✅ | ✅ front and back, CPU and GPU [6] | 🧑 rack camera saw no face [6] | 🧑 needs a device with a face in view; hosted emulators expose no passed-through webcam [14] | ❌ rotation and backgrounding explicitly untested [6] | ❌ |
| Linux x64 | ✅ CPU [7] | ✅ [7] | ✅ [7] | ✅ real V4L2 device in CI, every push [8] | ✅ 12+ face frames per session [8] | ✅ median 0.24%, mirrored 8% [8] | ❌ | ❌ |
| Windows x64 | ✅ CPU [7] | ✅ [7] | ✅ [7] | ✅ Media Foundation virtual camera in CI, every pull request [12] | ✅ 12 face frames per session [12] | ✅ median 0.31%, mirrored 4.6% [12] | ❌ | ❌ |

Mirrored-hypothesis figures recorded before 2026-09-22 (Linux 8%, iOS 5.1%)
compared landmarks under the same labels. The IMAGE task labels a mirrored
face by the side of the picture, so both oracles now read each hypothesis
under the labels it implies [11]; direct medians are unchanged and the Linux
job's mirrored figure is now 4.8%.

iOS Firefox user-agent CPU initialization is regression-tested in Chromium
CI [13]: the actual task worker receives the iOS UA and completes construction
and inference without a document. This is not physical iOS validation. The
four iOS Firefox/Safari CPU/GPU hand tests remain pending after deployment;
Safari GPU and the reported Firefox preview letterboxing are not resolved.

Hardware-free coverage that runs on every platform in `flutter test`:
`gallery/test/live_camera_controller_test.dart` pins frame skipping,
timestamp monotonicity, stop draining in-flight inference, superseded starts,
failure handling, camera switching and idempotent close against a scripted
camera platform; `camera_geometry_test.dart` and `camera_frame_test.dart`
cover the projection math and pixel conversion.

## Records

1. `validations/2026-09-18-web-face-landmarker/` and the Web workflow.
2. `validations/2026-09-18-web-gpu/` (`physical-camera-gpu-local.json`).
3. `validations/2026-09-14-face-landmarker-1.0.1/` and the macOS workflow's
   GPU comparison job.
4. Commit `6d38854` records 1080p CPU/Metal cadence measurements on an M4 Max.
5. `validations/2026-09-17-ios-official-gpu/` (`camera-smoke.json`).
6. `validations/2026-09-18-android-face-sdk/`.
7. `validations/2026-09-18-desktop-cpu-gallery/`.
8. `validations/2026-09-21-linux-real-camera/` and the `Linux real camera` workflow.
9. `validations/2026-09-21-macos-real-camera/`.
10. `validations/2026-09-22-ios-real-camera/`.
11. `validations/2026-09-22-web-alignment/` and the Web workflow.
12. `validations/2026-09-22-windows-real-camera/` and the `Windows real camera` workflow.
13. `validations/2026-09-22-web-ios-user-agent/`: red/green CPU worker regression,
    plus existing Chromium CPU/GPU and Firefox CPU checks.
14. `validations/2026-09-22-android-emulator-webcam-probe/`: negative result,
    0 guest cameras on API 30, 33, 34 and 35.

## Filling the 🧑 cells

**iOS (done 2026-09-22; repeat after camera-path changes).** Prepare for the
device, run the real-camera test with your face in view, and keep the report:

```sh
python3 -B gallery/tool/prepare.py --target ios/arm64 --tasks face_landmarker
cd gallery && flutter pub get
MEDIAPIPE_CAMERA_REPORT=$PWD/../build/codex-tmp/ios-real-camera/report.json \
  flutter test -d <iphone-id> integration_test/real_camera_test.dart --reporter expanded
```

The test takes a native screenshot, so the alignment oracle runs on the phone.
Copy `report.json` to `validations/<date>-ios-real-camera/` and update the row.

**macOS (camera done 2026-09-21; soak still open).** `real_camera_test.dart`
records capture and face frames but cannot screenshot the preview texture on
macOS, so alignment stays a visual check. The soak has not been retained yet:

```sh
python3 -B gallery/tool/prepare.py --target macos/arm64 --tasks face_landmarker
cd gallery && MEDIAPIPE_CAMERA_REPORT=$PWD/../build/codex-tmp/macos-real-camera/report.json \
  flutter test -d macos integration_test/real_camera_test.dart --reporter expanded
cd ../packages/mediapipe-task-vision && python3 -B tool/test_camera_soak.py
```

Resolved on 2026-09-21: Xcode 27's `codesign` changed the signed dylib's
bytes, so the official runtime is now pinned by its unsigned image
(`unsignedMachOSha256`, same digest in Python and Dart) and the gallery's
macOS deployment target is 14.0, the runtime's minimum.

**Windows (done in CI 2026-09-22).** The `Windows real camera` workflow builds
the Media Foundation fixture camera in `gallery/tool/windows/vcam`, allows
camera access, and runs `real_camera_test.dart` against it with the desktop
screenshot oracle; its README covers running it on a Windows 11 machine. A
physical webcam is still worth one manual pass, since its formats differ:

```sh
python -B gallery/tool/prepare.py --target windows/x64 --tasks face_landmarker
cd gallery && flutter run -d windows --release -t tool/live_face_camera_smoke.dart
```

**Android with a face.** A physical device you can point at a person,
running `real_camera_test.dart` with the official SDK adapter. The emulator
route was tried on 2026-09-22 and does not work on hosted runners: the
v4l2loopback device reaches the emulator as `webcam0`, but the guest reports
0 cameras on every image tried [14].
