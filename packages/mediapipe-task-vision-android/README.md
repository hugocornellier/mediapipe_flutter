Android vision task adapter for `mediapipe_flutter_vision`. It uses Google's
released `com.google.mediapipe:tasks-vision:1.0.0` Java/JNI SDK with its original
task graph. Creation, IMAGE/VIDEO inference and disposal run on one executor
thread, including GPU context ownership. GPU errors propagate without CPU fallback.

Add this Flutter plugin alongside `mediapipe_flutter_vision`. The SDK is the
default on Android arm64 and x86_64, so the app only lists its tasks:

```yaml
dependencies:
  mediapipe_flutter_vision:
    path: ../packages/mediapipe-task-vision
  mediapipe_flutter_vision_android:
    path: ../packages/mediapipe-task-vision-android
hooks:
  user_defines:
    mediapipe_flutter_vision:
      tasks: [face_landmarker, hand_landmarker] # any of the served tasks
```

`official_android_sdk: false` selects the source-built Face Detector and Face
Landmarker runtime instead (tool/build_android.py).

Flutter registers the adapter automatically, and the public task APIs stay the
same. Android 24 or later is required. The SDK serves every vision task except
the point-based Interactive Segmenter Legacy, which Google's 1.0.0 Android task
cannot run correctly (it ignores the keypoint; upstream-issues.md UP-020). The
selection avoids loading the source-built MediaPipe runtime into the same
process. Every task runs on the x86_64 emulator's CPU in CI, and nightly on CPU
and GPU on a Pixel 8a (Mali), a Galaxy S24 (Adreno) and a Galaxy A12 (PowerVR)
in Firebase Test Lab (.github/workflows/android-face-testlab.yml). See
[the status table](../mediapipe-task-vision/tool/VISION_TASKS_STATUS.md).

Segmentation masks travel from native memory over a separate binary channel,
because one frame's DeepLab masks can outgrow the Java heap.

File input applies EXIF orientation. Pixel input supports RGB, RGBA and BGRA
with row padding. Alpha is ignored and input RGB values are preserved in an
opaque Android bitmap. Output lists are copied before native resources close.
The gallery converts Android YUV_420_888 camera planes to RGBA, respecting each
plane's row and pixel strides. Camera rotation is handled by MediaPipe.

Test Lab instructions and validation scope are in
[`gallery/tool/ANDROID_FACE_TESTLAB.md`](../../gallery/tool/ANDROID_FACE_TESTLAB.md).
