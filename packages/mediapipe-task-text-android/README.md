# MediaPipe Android text tasks

Flutter Android plugin that runs Text Classifier, Text Embedder and Language Detector from `mediapipe_flutter_text` on
Google's unmodified **com.google.mediapipe:tasks-text 1.0.0** SDK. Add it
next to `mediapipe_flutter_text`; it registers itself, and the public API
is the same as on other platforms. One worker thread owns every task.

Tasks run on CPU, as Google's Android text tasks do. Like
`mediapipe_flutter_vision_android`, the plugin swaps the SDK's
protobuf-javalite for the full protobuf-java runtime Google's vision SDK needs
(google-ai-edge/mediapipe#6348), so the three plugins coexist in one app.
Google's single `libmediapipe_tasks_jni.so` (from tasks-core) runs the
vision, text and audio graphs alike.

Google's tasks-text AAR also ships `libmediapipe_tasks_textgenai_jni.so`
(about 14 MB per ABI), which these three tasks never load. An app that wants
it out can add to its `android/app/build.gradle`:

```groovy
android {
    packaging { jniLibs { excludes += ['**/libmediapipe_tasks_textgenai_jni.so'] } }
}
```

CI runs `gallery/integration_test/sdk_text_audio_test.dart` on an x86_64
emulator: every task against Google's reference outputs for the same inputs.
