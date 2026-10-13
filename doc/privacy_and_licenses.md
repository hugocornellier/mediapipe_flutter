# Privacy and licenses

## What is downloaded, and from where

Inference runs on the device: images, audio and text you pass to a task are
not sent anywhere by these packages. The packages do download software and
models, each pinned to one SHA-256 (SHA-384 for browser files) and rejected
if the bytes differ.

At build time, the build hooks fetch the native runtime for the target:

| What | Host |
| --- | --- |
| Google's per-family MediaPipe libraries (Android, iOS, macOS, Linux, Windows), development builds posted unmodified for testing as a pre-release of `hugocornellier/mediapipe_flutter_native` until Google publishes them | `github.com`, which redirects to `release-assets.githubusercontent.com` |
| Decision Maker's Windows library, from Google's 1.1.0 Python wheel, since Google's per-family build has no Windows decision library | `files.pythonhosted.org` |

At run time:

| What | Host |
| --- | --- |
| Pinned models, only when the app sets `ModelStore.allowDownloads = true` or calls `ModelStore` itself; bundled models are fetched at build time by `dart run mediapipe_core:bundle_models` instead | `storage.googleapis.com`; the EmbeddingGemma 2 models (Decision Maker and Retrieval) from `huggingface.co`, which redirects to its CDN (`*.hf.co`) |
| Google's browser runtime (web only), unless self-hosted | `cdn.jsdelivr.net` |

`hooks.user_defines.mediapipe_core.asset_source`, `ModelStore(source: ...)`
and self-hosting the browser runtime replace these hosts with your own; see
[platform setup](platform_setup.md).

### Google's usage logging

Google's MediaPipe runtimes send usage metrics to Google: the task, its
running mode, latencies and input counts, never the images, audio or text it
processes. Google's NOTICE opens with its MediaPipe Tasks privacy notice,
which makes the app's developer responsible for getting users' informed
consent where the law requires it. The packages cannot turn the logging off.

| Where | What the packages bundle | Usage logging |
| --- | --- | --- |
| macOS, Linux, Windows | Google's per-family 1.1.1 libraries; on Windows, Decision Maker uses its 1.1.0 wheel's library | An uploader to `https://play.googleapis.com/log` in every library. Observed uploading on macOS with Google's October 5 build, one request per task close with the process name in the User-Agent, and on Windows with its 1.0.0 library ([UP-025](../upstream-issues.md#up-025-windows-task-closes-wait-for-googles-usage-logging-upload)); on Linux read from the binary, not run |
| iOS | Google's per-family 1.1.1 libraries | The same uploader. Observed uploading on the iOS Simulator with Google's October 8 build: one request per task close, with the app's bundle ID and version in the User-Agent |
| Android | Google's per-family 1.1.1 libraries | The same uploader, which reaches the network through Java. A library loaded through FFI, as here, cannot reach it: tasks log `Failed to get JNIEnv in AndroidNetworkManager::OnAttachedToJvm()` and, as far as the logs and the binary show, send nothing. No network capture has confirmed it |
| Browsers | Google's JavaScript runtimes | Requests from the page to `https://odml.pa.googleapis.com/v1/log` when a task closes and every 60 seconds while one is open (observed with Face Detector) |

Block those endpoints if your policy requires it: inference is unaffected. A
task's close waits for its upload, so refuse the connection (for example
through the hosts file) rather than drop its packets, which makes each close
wait for the upload to time out (about 4 seconds on iOS).

## Licenses

- This repository's source: [Apache-2.0](../LICENSE), with upstream notices
  retained.
- Google's MediaPipe runtimes: Apache-2.0. `mediapipe_core` carries the
  `LICENSE` and `NOTICE` Google ships with the libraries it pins
  (`third_party/`, identical for every family), which apps redistribute with
  the runtime. The vision package also keeps OpenCV's
  carotene notices (`third_party/OPENCV_CAROTENE_NOTICES`) until Google
  confirms whether its libraries need them.
- Google's MediaPipe task models (the pins in each family's `models.dart`):
  Apache-2.0, per Google's model cards, except the Gemma-based text models.
- EmbeddingGemma, Proofreader and Summarizer are Gemma models, under the
  [Gemma Terms of Use](https://ai.google.dev/gemma/terms) and its
  [Prohibited Use Policy](https://ai.google.dev/gemma/prohibited_use_policy).
  An app that ships or downloads them must pass those terms on to its users.

`python3 -B packages/mediapipe-core/tool/mirror_runtime_assets.py` lists every
pinned runtime and model with its license.
