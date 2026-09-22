# Fixture camera for Windows CI

Hosted Windows runners have no webcam. This directory builds a Media
Foundation virtual camera, **MediaPipe Fixture**, that shows the licensed test
portrait (`packages/mediapipe-task-vision/test/fixtures/face_detection/landmark-ex1.jpg`,
letterboxed into 640x480 at 30 fps, the same frame the Linux job streams into
v4l2loopback). The gallery's `integration_test/real_camera_test.dart` then
opens it through `camera_desktop`'s capture engine like any webcam.

- `vcam_source.cpp`: the media source, an in-process COM server the Frame
  Server services load. It offers RGB32 and NV12.
- `vcam_host.cpp`: `start` creates and starts the camera with
  `MFCreateVirtualCamera` (session lifetime, so it exists while the host
  runs), `list` prints capture devices, `smoke` reads frames the way
  `camera_desktop` opens a device and compares them with the fixture.
- `make_fixture.ps1`, `build.ps1`: letterbox the portrait with GDI+, embed it
  as a resource, and compile both with the Visual Studio C++ tools.

`.github/workflows/windows-camera.yaml` builds it, registers the DLL under
HKLM with `regsvr32`, starts the host, checks the device is enumerated and
streams, then runs the gallery test. To try it on a Windows 11 machine, from
an elevated PowerShell at the repository root:

```powershell
gallery/tool/windows/vcam/build.ps1 -Out C:\mediapipe-vcam
regsvr32 C:\mediapipe-vcam\mediapipe_vcam.dll
C:\mediapipe-vcam\vcam_host.exe start   # keep running; the camera lives with it
C:\mediapipe-vcam\vcam_host.exe smoke 30 frame.bmp   # in another window
```

## Provenance

Adapted from Microsoft's VirtualCamera sample, commit
[`c1bd9e099f15c2ecf735216c7dd065cdb02a803f`](https://github.com/microsoft/Windows-Camera/tree/c1bd9e099f15c2ecf735216c7dd065cdb02a803f/Samples/VirtualCamera)
of `microsoft/Windows-Camera` (`SimpleMediaSource`, `SimpleMediaStream`,
`SimpleFrameGenerator`, `VirtualCameraMediaSourceActivate`), MIT License,
retained in `LICENSE-Microsoft.txt`. Changes: one stream showing a still
portrait instead of a moving gradient, RGB32 offered before NV12, frames paced
at the declared rate, no custom KS property or camera wrapping, and C++/WinRT
and WIL replaced with WRL so it builds with the Windows SDK alone.
