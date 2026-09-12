## Unreleased

* Implement official MediaPipe v1.0.0 Face Detector on macOS arm64, CPU IMAGE/VIDEO modes.
* Accept files, RGB/RGBA/BGRA pixels with row strides, model paths, and model bytes.
* Validate video timestamps and compare frame sequences with official Python outputs.
* Run inference on a worker isolate with owned results and awaited disposal.
* Add pinned native builds and tests against official Python reference results.
* Download and verify a pinned public native archive, with cached offline reuse.
* Test fresh Flutter debug/release consumers without native build tools.
* Add a macOS `camera_desktop` example with live overlays and hardware checks.
* Additional platforms/modes remain pending.
