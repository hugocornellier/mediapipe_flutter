Android Face Landmarker and Hand Landmarker adapter for `mediapipe_flutter_vision`. It uses Google's
released `com.google.mediapipe:tasks-vision:1.0.0` Java/JNI SDK with its original
task graph. Creation, IMAGE/VIDEO inference and disposal run on one executor
thread, including GPU context ownership. GPU errors propagate without CPU fallback.

Add this Flutter plugin alongside `mediapipe_flutter_vision`, then select the SDK
in the application's pubspec:

```yaml
dependencies:
  mediapipe_flutter_vision:
    path: ../packages/mediapipe-task-vision
  mediapipe_flutter_vision_android:
    path: ../packages/mediapipe-task-vision-android
hooks:
  user_defines:
    mediapipe_flutter_vision:
      official_android_sdk: true
      tasks: [face_landmarker, hand_landmarker]
```

Flutter registers the adapter automatically. The public `FaceLandmarker` and
`HandLandmarker` `create`, `detectImage`, `detectForVideo` and `dispose` APIs
stay the same. Android 24 or later is required. This SDK selection supports
these two tasks only; it avoids loading the source-built MediaPipe runtime into
the same process. Hand Landmarker has run on an emulator's CPU so far; see
[its status](../mediapipe-task-vision/tool/HAND_LANDMARKER_STATUS.md).

File input applies EXIF orientation. Pixel input supports RGB, RGBA and BGRA
with row padding. Alpha is ignored and input RGB values are preserved in an
opaque Android bitmap. Output lists are copied before native resources close.
The gallery converts Android YUV_420_888 camera planes to RGBA, respecting each
plane's row and pixel strides. Camera rotation is handled by MediaPipe.

Test Lab instructions and validation scope are in
[`gallery/tool/ANDROID_FACE_TESTLAB.md`](../../gallery/tool/ANDROID_FACE_TESTLAB.md).
