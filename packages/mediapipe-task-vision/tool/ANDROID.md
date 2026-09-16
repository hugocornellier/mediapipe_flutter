# Android runtime candidate

The combined MediaPipe v1.0.0 C task runtime can be cross-built with the pinned
Android NDK `28.2.13676358`. This is a validation candidate. The Flutter package
does not yet declare Android task support or download an Android runtime.

From the repository root on macOS or Linux with Bazelisk and Python installed:

```sh
python3 -B packages/mediapipe-task-vision/tool/build_android.py --ndk <ndk-path>
```

The builder uses an isolated pinned checkout under
`build/codex-tmp/mediapipe-android`. A generated toolchain package registers the
NDK through upstream's pinned `rules_android_ndk`, and a recorded WORKSPACE
addition binds `android/crosstool`. A recorded task BUILD change selects the
existing C API export map for Android. The upstream OpenCV 4.12 Android SDK download
also receives an explicit SHA-256 pin. Unexpected source or overlay edits are
rejected. Task source and graph code remain unchanged.

Upstream Android GL internals are compiled because its GPU-disabled build
configuration still includes GL buffer code whose types it hides. Only CPU
inference is selected for validation; GPU inference is unvalidated.

The link also applies upstream's existing C API export map, which its BUILD
file normally enables only for Linux. Hiding internal C++/protobuf symbols
prevents a collision with Android's system protobuf during native loading.
Linker-generated protobuf section boundary symbols are hidden as well. Native
CPU task creation still initializes EGL, so these probes require a working GL
context even though they request CPU inference.

The output under `packages/mediapipe-task-vision/build/native/android/arm64-v8a/`
contains `libmediapipe.so`, `libopencv_java4.so`, `libc++_shared.so`, their notices,
and a manifest with hashes, flags, NDK provenance and overlay receipts. Build
checks require the complete C export set, the expected ELF architecture and
SONAMEs, dependency closure, and LOAD segments aligned for 16 KB pages. Models
remain separate.

Run basic native loading and face IMAGE inference checks on a booted arm64 test
device or emulator:

```sh
python3 -B packages/mediapipe-task-vision/tool/test_android_native.py \
  --ndk <ndk-path> --adb <sdk-path>/platform-tools/adb \
  --device emulator-5554 --require-page-size 16384
```

This compiles the existing native C ABI probes with Android host metadata and
pushes an isolated test directory under `/data/local/tmp/`. It checks one face
with six detector keypoints and a landmarker result containing 478 landmarks,
52 blendshapes and a 4×4 transform. Reports and logs are saved under root
`build/codex-tmp/android-native-*/`.

These count checks do not establish numerical reference parity, Flutter APK
packaging, VIDEO/lifecycle behavior, GPU support, camera support or physical
device performance. Those checks must precede a supported Android release and
consumer CI job.

The September 16 Android 16 arm64 emulator run passed both face probes on a
16 KB-page system. [Build and smoke receipts](validations/2026-09-16-android-native/)
record the exact runtime and dependency hashes. See UP010 in `upstream-issues.md`
for the initial crash and export-isolation workaround.
