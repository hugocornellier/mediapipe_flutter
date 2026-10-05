# iOS SDK adapter

`mediapipe_core`'s build hook compiles these Objective-C++ bridges into
one `mediapipe_ios` framework over Google's prebuilt MediaPipe 1.0.1 iOS
XCFrameworks (pinned in `lib/src/native_assets/ios_sdk.dart`). Google's
`MediaPipeTasksCommon` implements every task, so an app holds it once and
the vision, text and audio packages all bind this one image. No MediaPipe code
is compiled from source here.

- `vision_sdk_bridge.mm`: the vision tasks.
- `text_sdk_bridge.mm`: Text Classifier, Text Embedder (EmbeddingGemma
  included), Language Detector, Proofreader and Summarizer.
- `audio_sdk_bridge.mm`: Audio Classifier, in clips mode and in audio stream
  mode, whose delegate results it hands to the C callback.

`include/mediapipe/tasks/c/` holds unchanged copies of the MediaPipe C API
headers from https://github.com/google-ai-edge/mediapipe/tree/v1.0.0 (commit
`6d31f1ebc3284db74d211d62bdc4f0a0c29ea120`), licensed under Apache 2.0 like
the rest of this repository. The vision package's `tool/generate_bindings.dart`
generates its bindings from these same files.
