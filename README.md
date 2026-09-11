# mediapipe_flutter

MediaPipe Tasks for Flutter.

Private development fork of [google/flutter-mediapipe](https://github.com/google/flutter-mediapipe),
maintained by [Hugo Cornellier](https://github.com/hugocornellier). This repository
preserves the upstream Git history and license. It is an independent project and
is not an official Google package.

## Current status

This initial fork establishes the `mediapipe_flutter` name and local package
dependencies. The inherited native SDK downloads and build tooling still need
modernization. The four target tasks below are planned work, not implemented
features of this fork yet.

No packages from this fork have been published to pub.dev. Each package has
`publish_to: none` while the private development baseline is being established.

## Packages

This is a monorepo with separate task packages; there is no umbrella Dart package
yet. Package directories retain their upstream layout to preserve native header
paths and build-tool compatibility.

| Package | Directory | Inherited implementation |
| --- | --- | --- |
| `mediapipe_flutter_core` | [packages/mediapipe-core](packages/mediapipe-core/) | Shared task types, FFI helpers, and utilities |
| `mediapipe_flutter_text` | [packages/mediapipe-task-text](packages/mediapipe-task-text/) | Text classification, embedding, and language detection |
| `mediapipe_flutter_genai` | [packages/mediapipe-task-genai](packages/mediapipe-task-genai/) | Earlier MediaPipe LLM inference API |
| `mediapipe_flutter_vision` | [packages/mediapipe-task-vision](packages/mediapipe-task-vision/) | Incomplete scaffold |
| Audio | [packages/mediapipe-task-audio](packages/mediapipe-task-audio/) | Placeholder; no Dart package yet |

The upstream support table listed Android, iOS, and macOS for its implemented
text and GenAI tasks. Those platforms have not yet been revalidated for this
renamed fork, and the existing GenAI wrapper does not establish support for
current `.litertlm` models.

## Local development

Clone this private repository using an authenticated GitHub account. Dependencies
between the packages and their examples point to sibling directories, so they
resolve the renamed code from this checkout rather than upstream pub.dev releases.

For example, to work on the shared Dart package:

```sh
cd packages/mediapipe-core
dart pub get
dart analyze
dart test
```

Package-specific READMEs retain upstream API examples. Their native-assets and
SDK setup instructions describe the inherited implementation and require review
as the runtime is modernized.

## Initial development targets

- Modernize the build hooks and establish reproducible, versioned native SDKs.
- Add the stateful MagicTouch Interactive Segmenter API.
- Add Holistic Landmarker and its combined face, hand, and pose results.
- Add Text Summarizer and Text Proofreader with their current native backends.
- Validate each task against official MediaPipe reference outputs on the target
  platforms before publishing.

The checked-in SDK manifests currently reference April/May 2024 artifacts. The
inherited `make sdks` command discovers builds through a bucket whose listing
requires Google access; a maintainable public artifact source or build process
is needed for future updates. Upstream native CI remains gated to the upstream
repository until its build process is modernized.

## Upstream and license

See [UPSTREAM.md](UPSTREAM.md) for the source revision, remotes, and rename map.
The original [Apache-2.0 license](LICENSE), [AUTHORS](AUTHORS), and source copyright
notices are retained.
