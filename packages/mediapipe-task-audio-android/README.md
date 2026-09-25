# MediaPipe Android audio tasks

Flutter Android plugin that runs Audio Classifier (clips; the gallery feeds it microphone windows) from `mediapipe_flutter_audio` on
Google's unmodified **com.google.mediapipe:tasks-audio 1.0.0** SDK. Add it
next to `mediapipe_flutter_audio`; it registers itself, and the public API
is the same as on other platforms. One worker thread owns every task.

Tasks run on CPU, as Google's Android audio tasks do. Like
`mediapipe_flutter_vision_android`, the plugin swaps the SDK's
protobuf-javalite for the full protobuf-java runtime Google's vision SDK needs
(google-ai-edge/mediapipe#6348), so the three plugins coexist in one app.
Google's single `libmediapipe_tasks_jni.so` (from tasks-core) runs the
vision, text and audio graphs alike.

CI runs `gallery/integration_test/sdk_text_audio_test.dart` on an x86_64
emulator: YAMNet on Google's speech clips against its reference outputs.
