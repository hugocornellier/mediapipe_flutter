# Upstream provenance

- Source: https://github.com/google/flutter-mediapipe
- Branch: `main`
- Fork base: `d3e554eacc81bc469fad525f54ed533b2fc585e7`
- Private repository: https://github.com/hugocornellier/mediapipe_flutter

This is a standalone private repository containing the upstream Git history.
GitHub does not permit a private fork of a public repository within its fork
network. The local `upstream` remote tracks Google's original repository;
`origin` points to this private repository.

## Initial rename

| Upstream package | Fork package |
| --- | --- |
| `mediapipe_core` | `mediapipe_flutter_core` |
| `mediapipe_text` | `mediapipe_flutter_text` |
| `mediapipe_genai` | `mediapipe_flutter_genai` |
| `mediapipe_vision` | `mediapipe_flutter_vision` |

Dart imports, library entry points, generated-binding paths, build-hook asset
identities, documentation, and local dependencies follow the renamed packages.
Native MediaPipe symbols, SDK download URLs, and upstream license notices retain
their original identity. Existing package versions are preserved at this stage.

The root marker used by the build tooling is `.mediapipe_flutter-root`.

## Tracking upstream

```sh
git fetch upstream
git log --oneline HEAD..upstream/main
```

Review incoming changes before merging them because package identities differ.
The initial fork and rename do not add task implementations or replace native
SDKs. Use the upstream revision above when comparing inherited behavior.

## Initial validation

Checked with Dart 3.12.2 on macOS arm64:

- Core package: all 30 existing tests pass; analysis passes.
- Text package library and build tool: analysis passes.
- Core, text, and GenAI package dependencies resolve to this checkout's renamed
  core package. The GenAI example separately fails dependency resolution because
  its inherited `intl: ^0.19.0` conflicts with current Flutter's `intl: 0.20.2` pin.
- GenAI library analysis reports three inherited `annotate_overrides` notices.
- All 139 Dart source files were compared with the upstream base: only the
  intended identity substitutions, the GenAI library-name correction, and
  trailing whitespace differ.
- `LICENSE` and `AUTHORS` are byte-for-byte identical to the upstream versions.

Native inference and the unfinished vision scaffold were not validated by this
rename. Their implementation and runtime modernization remain separate work.

## Stable SDK recovery

The subsequent cleanup targets Flutter 3.44.8 stable / Dart 3.12.2. It migrates
the text and GenAI hooks to `hooks` / `code_assets`, pins native downloads with
SHA-256, and regenerates FFI bindings with ffigen 21 from the existing headers.
The native runtime remains the April/May 2024 upstream builds. Header filters
exclude unrelated host SDK declarations from generated bindings.

Text executor and public API tests now exercise real macOS arm64 inference;
the text example builds and its widget tests pass. The GenAI example resolves
dependencies and passes its Dart state tests, but LLM inference is unvalidated.
CI now runs on this fork. See the root README for commands and remaining work.

## Modern Face Detector

Vision now uses MediaPipe v1.0.0, commit
`6d31f1ebc3284db74d211d62bdc4f0a0c29ea120`, with unchanged C API headers and
the official BlazeFace short-range float16 version-1 model. Its ABI is separate
from the legacy core/text/GenAI structs. The native build keeps the official task
graph and calculators intact, statically links OpenCV 4.12.0 for CPU preprocessing,
and adjusts linking to retain C entry points and permit Dart/Flutter relocation.

Fixtures come from `face_detection_tflite` at
`50c784adaa9f40c722affb1d4412674f25e1fe0c`. Reference detections are generated
independently through Google's `mediapipe==1.0.0` Python API. The vision package
records model, fixture, and reference-library digests and provides native ABI,
inference, and Flutter bundling checks. Its runtime is currently source-built;
prebuilt releases and additional platforms/modes remain pending.
