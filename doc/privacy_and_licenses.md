# Privacy and licenses

## What is downloaded, and from where

Inference runs on the device: images, audio and text you pass to a task are
not sent anywhere by these packages. The packages do download software and
models, each pinned to one SHA-256 (SHA-384 for browser files) and rejected
if the bytes differ.

At build time, the build hooks fetch the native runtime for the target:

| What | Host |
| --- | --- |
| Google's MediaPipe wheels (Linux, Windows) | `files.pythonhosted.org` |
| Google's MediaPipe iOS SDK archives | `dl.google.com` |
| Google's macOS engine repackaged for Flutter, the macOS face runtimes, and the iOS face runtime an app gets only with `official_ios_sdk: false` | `github.com/hugocornellier/mediapipe_flutter_native` releases |
| Google's MediaPipe Android SDKs | Google's Maven repository, through Gradle |

At run time:

| What | Host |
| --- | --- |
| Pinned models, on first use of `model:` or `ModelStore` | `storage.googleapis.com` |
| Google's browser runtime (web only), unless self-hosted | `cdn.jsdelivr.net` |

`hooks.user_defines.mediapipe_core.asset_source`, `ModelStore(source: ...)`
and self-hosting the browser runtime replace these hosts with your own; see
[platform setup](platform_setup.md).

### Google's usage logging

Google's native MediaPipe libraries contain a usage-logging client. With
Google's Windows library it was observed posting to
`https://play.googleapis.com/log` when a task closes
([UP-025](../upstream-issues.md#up-025-windows-task-closes-wait-for-googles-usage-logging-upload));
the packages cannot turn it off. Block that endpoint if your policy requires
it: inference is unaffected.

## Licenses

- This repository's source: [Apache-2.0](../LICENSE), with upstream notices
  retained.
- Google's MediaPipe runtimes: Apache-2.0. The downloaded archives carry
  Google's `LICENSE` and `NOTICE` files, which apps redistribute with the
  runtime.
- Google's MediaPipe task models (the pins in each family's `models.dart`):
  Apache-2.0, per Google's model cards, except the Gemma-based text models.
- EmbeddingGemma, Proofreader and Summarizer are Gemma models, under the
  [Gemma Terms of Use](https://ai.google.dev/gemma/terms) and its
  [Prohibited Use Policy](https://ai.google.dev/gemma/prohibited_use_policy).
  An app that ships or downloads them must pass those terms on to its users.

`python3 -B packages/mediapipe-core/tool/mirror_runtime_assets.py` lists every
pinned runtime and model with its license.
