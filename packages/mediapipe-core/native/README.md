# MediaPipe C API headers

`include/mediapipe/tasks/c/` holds unchanged copies of the MediaPipe C API
headers the vision package's bindings come from, taken from
https://github.com/google-ai-edge/mediapipe/tree/v1.0.0 (commit
`6d31f1ebc3284db74d211d62bdc4f0a0c29ea120`) and licensed under Apache 2.0 like
the rest of this repository. The vision package's `tool/generate_bindings.dart`
generates its bindings from them, and its `tool/abi_check.cc` checks the struct
sizes those bindings assume. They are not published: the text and audio
bindings follow Google's Python ctypes instead, and no hook compiles against
them.

The task families bind Google's prebuilt per-family libraries, which their
build hooks bundle (`lib/src/native_assets/family_runtimes.dart`); no
MediaPipe code is compiled here.
