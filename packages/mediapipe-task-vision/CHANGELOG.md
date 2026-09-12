## Unreleased

* Add official MediaPipe 1.0.1 MagicTouch Interactive Segmenter for macOS arm64 CPU, macOS 14+.
* Expose stateful image replacement and complete positive/negative/lasso stroke histories with owned confidence masks.
* Add an optional checksum-verified public runtime download; face-only defaults remain unchanged.
* Add a macOS image editor with bounded pending inference, undo/clear, file selection and mask overlays.
* Validate against official Python masks, test fresh Flutter debug/release consumers, and record CPU benchmarks.
* Reject macOS segmenter GPU requests explicitly because the official stroke shader fails.

* Add local CPU runtime builds and Flutter IMAGE/VIDEO integration coverage for arm64 iOS simulators.
* Add a simulator image demo with face detection, mesh, irises and optional expression/transform outputs.
* Keep simulator/device artifact selection distinct and reject unsupported iOS GPU requests explicitly.

* Add per-task `VisionDelegate.cpu` / `.gpu` selection for Face Detector and Landmarker.
* Bundle Metal and CPU in one runtime per task; keep official models and graphs unchanged.
* Add independent Metal reference tests, RGB-to-RGBA input conversion, and camera delegate switching.
* Isolate native Objective-C names and reject stale CPU-only artifacts.
* Implement official MediaPipe v1.0.0 Face Detector on macOS arm64, CPU IMAGE/VIDEO modes.
* Accept files, RGB/RGBA/BGRA pixels with row strides, model paths, and model bytes.
* Validate video timestamps and compare frame sequences with official Python outputs.
* Run inference on a worker isolate with owned results and awaited disposal.
* Add pinned native builds and tests against official Python reference results.
* Download and verify a pinned public native archive, with cached offline reuse.
* Test fresh Flutter debug/release consumers without native build tools.
* Add a macOS `camera_desktop` example with live overlays and hardware checks.
* Additional platforms/modes remain pending.
