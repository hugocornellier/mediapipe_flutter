# Native provenance

- MediaPipe: https://github.com/google-ai-edge/mediapipe/tree/v1.0.0
- Commit: `6d31f1ebc3284db74d211d62bdc4f0a0c29ea120`
- Bazel: 7.4.1, from that release's `.bazelversion`.
- Target: `//mediapipe/tasks/c/vision/face_detector:libface_detector.dylib`.
- OpenCV: 4.12.0, commit `49486f61fb25722cbcf586b7f4320921d46fb38e`.
- Model: official BlazeFace short-range float16 version 1; URL and digest are in
  `lib/models.dart`.

The ten headers under `mediapipe/` are unchanged copies from that commit.
They define the modern C ABI separately from the legacy 2024 core/text/GenAI
bindings. Do not substitute those packages' base options or image structs.

`tool/build_native.py` compiles the official CPU task with static OpenCV core
and imgproc. Its external-repository override supplies those static libraries;
no MediaPipe graph, calculator, model, or C implementation is patched.

Linker flags retain the Face Detector/image entry points (otherwise the upstream
target dead-strips them), restrict exports to `Mp*`, and reserve install-name
space for Dart/Flutter relocation. Only macOS system frameworks/libraries remain
as dynamic dependencies. Every build verifies C exports, ABI sizes, and portrait
inference before preparing a native release candidate with a SHA-256 manifest.
The build is source/version pinned; byte-identical output across Xcode versions
is not claimed.

`LICENSE` and `NOTICE` were copied from Google's official MediaPipe 1.0.0
distribution. They include notices for the larger upstream distribution.
The native release archive also includes OpenCV's installed license directory.

Reference detections use Google's unmodified macOS arm64 Python wheel:
`mediapipe-1.0.0-py3-none-macosx_11_0_arm64.whl`.

- Wheel SHA-256: `7ee4783be41b2de345e1eb71e2f7e7c159a50ed5c283e60ccb8f5a6027c70a82`.
- Original `mediapipe/tasks/c/libmediapipe.dylib` SHA-256:
  `aa1314b6cc3eb2ce3b610808433930c016e19cdc0f62cbb3f10cc7e912b6f72f`.

The wheel is an independent oracle, not the application runtime. Its library
contains every task and lacks the Mach-O header padding Dart bundling requires.
