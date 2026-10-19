# MediaPipe C API headers

`include/` holds Google's MediaPipe Tasks C API headers, unmodified, as
Google ships them with the per-family libraries the hooks bundle
(`lib/src/native_assets/family_runtimes.dart`). `BUILD_INFO` names the build
they come from: MediaPipe 1.2.0, Google's nightly of 2026-10-18. They are licensed under
Apache 2.0 like the rest of this repository.

Google ships one header tree per family. `include/` merges the five; a header
that several families ship is byte-identical in each. Includes are relative to
`include/` (`core/base_options.h`, `vision/face_detector/face_detector.h`),
and `mediapipe_tasks_<family>.h`, which Google generates without a license
header, includes a family's whole API.

The vision package's `tool/generate_bindings.dart` generates its bindings from
them, and its `tool/abi_check.cc` checks the struct sizes those bindings
assume. The other families' bindings are written by hand and match these
headers. The headers are not published, and no hook compiles against them.

Until the October 16 build Google's headers left out three APIs the
libraries export: the Proofreader and Summarizer (text) and the modern
Interactive Segmenter (vision). Their bindings were written from Google's
Python ctypes before the headers shipped.

To update, replace `include/` and `BUILD_INFO` with the headers of the build
the hooks pin, merging the families' trees, then run `make generate_vision`
and `make test_vision`.
