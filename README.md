# mediapipe_flutter

MediaPipe Tasks for Flutter. An independent, private development fork of
[google/flutter-mediapipe](https://github.com/google/flutter-mediapipe), maintained
by [Hugo Cornellier](https://github.com/hugocornellier). This is not an official
Google package. No packages from this fork have been published to pub.dev.

## Development baseline

Use **Flutter 3.44.8 stable / Dart 3.12.2**. Package SDK constraints start at
Dart 3.12. Build hooks use the supported `hooks` and `code_assets` APIs; no
experimental flags or global Flutter configuration changes are needed.

Text classification, text embedding, and language detection run on macOS arm64.
Tests exercise the native executors, their reference numeric outputs, and the
public isolate-based APIs. The macOS text example also builds on this baseline.

The official MediaPipe v1.0.0 Face Detector also runs on macOS arm64 in CPU IMAGE
mode, with tests against Google's Python reference outputs. Native builds use
pinned upstream source and static OpenCV; no task pipeline or model is patched.

This is a development baseline. GenAI inference and mobile platforms still need
validation, and the new vision runtime needs a published prebuilt artifact.

## Packages and platform status

| Package | Directory | Status |
| --- | --- | --- |
| `mediapipe_flutter_core` | [mediapipe-core](packages/mediapipe-core/) | Shared types, FFI utilities, build-time download helpers |
| `mediapipe_flutter_text` | [mediapipe-task-text](packages/mediapipe-task-text/) | Three text tasks validated on macOS arm64 |
| `mediapipe_flutter_genai` | [mediapipe-task-genai](packages/mediapipe-task-genai/) | Legacy LLM wrapper; tooling updated, inference unvalidated |
| `mediapipe_flutter_vision` | [mediapipe-task-vision](packages/mediapipe-task-vision/) | Face Detector: macOS arm64, CPU still images |
| Audio | [mediapipe-task-audio](packages/mediapipe-task-audio/) | Placeholder, no Dart package |

Text runtime artifacts exist for macOS arm64/x64, Android arm64, and iOS arm64
devices. GenAI artifacts exist for macOS arm64, Android arm64, and iOS arm64
devices. Artifact availability does not establish tested platform support.
There are no iOS simulator, Windows, Linux, or web task runtimes in this baseline.
Unsupported native targets fail with an explicit build error.

## Packaging

Depend on the task packages you use. At build time, the text and GenAI packages download
its native library for the target platform, verifies SHA-256, and lets Dart or
Flutter bundle it with the application. Verified downloads are cached under
the hook's shared output directory. Partial or mismatched downloads are rejected.

Model files remain separate. Applications bundle or download only the models they
need; runtime hooks do not fetch models. `make models` downloads the three pinned
text models and the official BlazeFace short-range float16 version-1 face model.

Text/GenAI native libraries remain the inherited April/May 2024 Google-hosted builds.
Their URLs and hashes are checked in, and FFI bindings are regenerated from the
existing headers. This tooling migration does not upgrade the native runtime.
The shared `native_assets.dart` helpers are imported by hooks, not by task runtime
entry points.

Vision currently bundles a locally built Face Detector library. `make native_vision`
builds the pinned MediaPipe v1.0.0 source with static OpenCV 4.12.0 and prepares a
release archive with its SHA-256 manifest and notices. The library is about
11.4 MB, plus a separate 224 KB model. Publishing that archive and configuring a
verified build-time download is still pending; consumers do not yet have a
download-only installation path for vision.

## Local development

Install Xcode and `brew install bazelisk cmake ninja` for the native vision build.
From the repository root:

```sh
make get
make models
make native_vision
make analyze
make test_only
make build_text
make test_vision_flutter
```

Or run the entire macOS CI sequence with `make ci`. To launch the text example,
run `make example_text`.

Other targets:

- `make test`: fetch models, build the vision runtime, and run the tests.
- `make format` / `make check_format`: apply / check Dart formatting.
- `make generate`: regenerate all implemented task bindings from checked-in headers.
- `make test_vision_flutter`: generate a macOS host and verify debug/release bundling.
- `make headers`: maintainer-only header import from a local MediaPipe checkout.
- `make sdks`: legacy Google bucket discovery, requiring Google access; writes
  candidate manifests without replacing the reviewed runtime pins.

Dependencies between packages and examples use local paths. The examples'
model assets and build outputs are ignored by Git. CI runs on pull requests and
pushes to this fork's `main`, using the same pinned stable SDK.

The `hooks` dependency is capped below 2.1 because newer releases require
`meta` newer than Flutter 3.44's SDK pin. GenAI's Freezed/Bloc major migrations
are deferred with its runtime recovery.

## Remaining work

- Publish the reviewed Face Detector native artifact and pin its download URL.
- Add VIDEO/LIVE_STREAM modes and a camera demo; camera capture remains an app
  dependency rather than a requirement for still-image inference.
- Audit inherited text isolate error propagation and native-result ownership
  before publishing. Successful inference tests do not cover invalid-model
  recovery or all lifecycle paths.
- Validate Intel macOS and mobile device builds and inference.
- Recover or replace the legacy GenAI backend separately; its example tests
  cover Dart state, not LLM inference. Current `.litertlm` support is not implied.
- Validate loading multiple task libraries together. The inherited standalone
  libraries may duplicate native registrations.
- Establish a maintainable native build/release source beyond the inherited
  Google-hosted artifacts.

## Upstream and license

See [UPSTREAM.md](UPSTREAM.md) for provenance and the rename map. The original
[Apache-2.0 license](LICENSE), [AUTHORS](AUTHORS), and copyright notices are retained.
