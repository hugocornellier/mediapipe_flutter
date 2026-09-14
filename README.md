# mediapipe_flutter

MediaPipe Tasks for Flutter. An independent development fork of
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

**EmbeddingGemma 300M** runs Google's modern MediaPipe 1.0.1 pipeline on macOS
arm64 CPU, macOS 14+. It provides owned 768-value embeddings, all eight official
formatting modes and optional output quantization. Run `make example_embedding`
for sentence comparison. Fresh Flutter debug/release integration tests compare
all 17 cases against official Python outputs and verify coexistence with vision.

The official MediaPipe v1.0.0 Face Detector and Face Landmarker run on macOS arm64
in CPU and Metal GPU IMAGE/VIDEO modes, with tests against Google's Python reference outputs. A live
camera example uses `camera_desktop`, with the full 478-point mesh and irises. Native builds use
pinned upstream source and static OpenCV; no task pipeline or model is patched.
Both tasks accept `delegate: VisionDelegate.cpu` (default) or `VisionDelegate.gpu`.
The camera demo exposes the same choice; each task download contains both backends.

The optional **MagicTouch Interactive Segmenter** uses Google's official 1.0.1
stateful image/stroke pipeline on macOS arm64, macOS 14+, CPU. A separate image
editor supports positive, negative and lasso strokes, undo and mask overlays.
Run `make example_segmenter`; see the
[segmenter guide](packages/mediapipe-task-vision/tool/INTERACTIVE_SEGMENTER.md).

This is a development baseline. GenAI inference and mobile platforms still need
validation. Public prebuilt runtimes are available for both macOS arm64 face
tasks and the optional segmenter. The face tasks also have a validated local
arm64 iOS simulator CPU target; simulator archives are not yet published.

## Packages and platform status

| Package | Directory | Status |
| --- | --- | --- |
| `mediapipe_flutter_core` | [mediapipe-core](packages/mediapipe-core/) | Shared types, FFI utilities, build-time download helpers |
| `mediapipe_flutter_text` | [mediapipe-task-text](packages/mediapipe-task-text/) | Modern EmbeddingGemma CPU + three legacy text tasks validated on macOS arm64; choose one runtime generation per app |
| `mediapipe_flutter_genai` | [mediapipe-task-genai](packages/mediapipe-task-genai/) | Legacy LLM wrapper; tooling updated, inference unvalidated |
| `mediapipe_flutter_vision` | [mediapipe-task-vision](packages/mediapipe-task-vision/) | Face tasks: macOS CPU/Metal + local iOS simulator CPU; optional macOS CPU MagicTouch editor |
| Audio | [mediapipe-task-audio](packages/mediapipe-task-audio/) | Placeholder, no Dart package |

Text runtime artifacts exist for macOS arm64/x64, Android arm64, and iOS arm64
devices. GenAI artifacts exist for macOS arm64, Android arm64, and iOS arm64
devices. Artifact availability does not establish tested platform support.
There are no published iOS simulator, Windows, Linux, or web task runtimes in this baseline.
Unsupported native targets fail with an explicit build error.

## Packaging

Depend on the task packages you use. At build time, each implemented task package
downloads its native library for the target platform, verifies SHA-256, and lets Dart or
Flutter bundle it with the application. Verified downloads are cached under
the hook's shared output directory. Partial or mismatched downloads are rejected.

Model files remain separate. Applications bundle or download only the models they
need; runtime hooks do not fetch models. `make models` downloads the three pinned
text models, BlazeFace short-range, and the complete Face Landmarker float16
version-1 bundle (FaceMesh V2), plus the MagicTouch int8 version-1 task bundle
and EmbeddingGemma 300M mixed int4/int8 version-1 bundle.

Legacy text/GenAI native libraries remain the inherited April/May 2024 Google-hosted builds.
Their URLs and hashes are checked in, and FFI bindings are regenerated from the
existing headers. This tooling migration does not upgrade the native runtime.
The shared `native_assets.dart` helpers are imported by hooks, not by task runtime
entry points.

Vision downloads separate 5.0 MB Face Detector and 5.5 MB Face Landmarker archives from the public
[native runtime repository](https://github.com/hugocornellier/mediapipe_flutter_native/releases).
The unpacked libraries are about 13.7 MB and 15.9 MB, with separate 224 KB and
3.8 MB models. Both tasks are enabled by default; apps can select a subset with
`hooks.user_defines.mediapipe_flutter_vision.tasks` in their pubspec. The camera
demo selects both face tasks. Both archive
and library digests are pinned. The hook extracts the runtime using Dart and
requires no Bazel, CMake, Ninja, or GitHub credentials. The Dart/Flutter source
repository is public; no packages from this fork are published to pub.dev yet.

Interactive Segmenter is **opt-in** with `tasks: [interactive_segmenter]`.
Both it and EmbeddingGemma require the app setting
`hooks.user_defines.mediapipe_flutter_core.tasks_runtime: true`. Core owns one
shared native asset: a 32.6 MB download / 100.9 MB library. Its existing immutable
release retains the `interactive-segmenter-v1.0.1-1` name. Separate models are
30.5 MB for MagicTouch and 183.8 MB for EmbeddingGemma. Face-only apps do not
download or bundle this runtime.

Enabling the modern runtime automatically omits the old text library. Loading
both generations caused native registration collisions, so combining them is
rejected. The legacy text APIs still work in apps using their default configuration.
See the [text package guide](packages/mediapipe-task-text/README.md) for usage.

`make native_vision` optionally builds pinned MediaPipe v1.0.0 and static OpenCV
4.12.0. The hook uses that verified local build when present. `make release_vision`
prepares a deterministic public archive with provenance, checksums, and notices.
See the vision package's [release instructions](packages/mediapipe-task-vision/tool/RELEASING.md).

## Local development

Install Xcode. From the repository root:

```sh
make get
make models
make analyze
make test_only
make build_text
make test_vision_flutter
```

The full source-build CI sequence, `make ci`, additionally requires Python 3 and
`brew install bazelisk cmake ninja`. To launch the text example, run `make example_text`.

Other targets:

- `make test`: fetch models and run the tests, downloading runtimes as needed.
- `make format` / `make check_format`: apply / check Dart formatting.
- `make generate`: regenerate all implemented task bindings from checked-in headers.
- `make test_vision_flutter`: generate a macOS host and verify debug/release bundling.
- `make test_vision_prebuilt`: test a fresh app against the public native download
  with native build tools blocked.
- `make example_vision`: download the model and launch the macOS live camera demo.
- `make build_vision_camera`: build the camera demo in release mode, without opening a camera.
- `make example_segmenter`: prepare the MagicTouch assets and open the macOS image editor.
- `make example_embedding`: prepare EmbeddingGemma and open sentence comparison.
- `make test_embedding_macos`: download models/runtimes into a fresh consumer and
  verify official outputs, shared bundling and task coexistence in debug/release.
- `make test_segmenter_prebuilt`: validate an isolated public-download consumer
  in debug/release and record CPU timings.
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

- Expose native LIVE_STREAM callbacks; the camera demo currently uses official
  VIDEO mode on a worker isolate. Camera capture remains an app dependency.
- Audit inherited text isolate error propagation and native-result ownership
  before publishing. Successful inference tests do not cover invalid-model
  recovery or all lifecycle paths.
- Validate Intel macOS and mobile device builds and inference.
- Recover or replace the legacy GenAI backend separately; its example tests
  cover Dart state, not LLM inference. Current `.litertlm` support is not implied.
- Migrate the legacy text APIs to the modern runtime before mixing them with
  modern tasks. GenAI coexistence remains unvalidated.
- Add the official Proofreader and Summarizer pipelines; their APIs are not yet exposed.
- Extend the pinned native build/release process to additional tasks and platforms.

## Upstream and license

See [UPSTREAM.md](UPSTREAM.md) for provenance and the rename map. The original
[Apache-2.0 license](LICENSE), [AUTHORS](AUTHORS), and copyright notices are retained.
