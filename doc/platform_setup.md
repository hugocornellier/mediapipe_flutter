# Platform setup

What an app needs on each platform beyond adding a family package. Google's
pinned models (`model: VisionModels.faceLandmarker` and the like) are bundled
with the app at build time by `dart run mediapipe_core:bundle_models` (see
[Build settings](#build-settings)), so an app that bundles its models needs no
network access at run time. The network settings below are only for apps
that set `ModelStore.allowDownloads = true` to download models at run time
instead.

## Android

- `minSdk` 24 or higher.
- To download models at run time, add the `INTERNET` permission to
  `android/app/src/main/AndroidManifest.xml`. Flutter adds it only to debug
  and profile builds, so a release build without it cannot download models:

  ```xml
  <uses-permission android:name="android.permission.INTERNET"/>
  ```

  When the connection fails, the `ModelDownloadException` names this
  permission.
- Tasks run through Google's MediaPipe Android SDKs (`tasks-vision`,
  `tasks-text`, `tasks-audio` 1.0.0), which Gradle fetches with the app.

## iOS

- iOS 15.0 or newer. Tasks run through an adapter over Google's MediaPipe
  1.0.1 iOS SDK that `mediapipe_core` builds; no CocoaPods or native plugin is
  involved. The first build downloads the SDK (about 1.4 GB of archives,
  cached afterwards) and extracts only the device or simulator slice it needs.
- On the iOS Simulator only the CPU is offered: Google's SDK aborts on the
  simulator's GPU path. Devices keep Metal.
- Downloaded models live in the app's Application Support folder, excluded
  from iCloud backup.

## macOS

- macOS 14.0 or newer on Apple Silicon.
- Text, audio and every vision task except Face Detector and Face Landmarker
  run on Google's macOS engine, which is opt-in because it adds about 95 MB:

  ```yaml
  hooks:
    user_defines:
      mediapipe_core:
        tasks_runtime: true
  ```

  Without it the app still builds (so `dart run` keeps working in iOS and
  Android apps developed on a Mac); creating one of those tasks then throws a
  `RuntimeUnavailableException` whose `fix` shows these lines.
- To download models at run time, a sandboxed app needs the network client
  entitlement in `macos/Runner/DebugProfile.entitlements` and
  `Release.entitlements`:

  ```xml
  <key>com.apple.security.network.client</key>
  <true/>
  ```

## Linux x64

- Google's Linux library loads EGL and OpenGL ES even for CPU inference. On
  Debian or Ubuntu: `sudo apt-get install libegl1 libgles2`. Without them,
  task creation fails with that instruction.
- GPU inference uses OpenGL ES where the vision status table lists it.

## Windows x64

- CPU inference. Google's Windows library may wait for a usage-log upload when
  a task is disposed
  ([UP-025](../upstream-issues.md#up-025-windows-task-closes-wait-for-googles-usage-logging-upload)).

## Web

- Workers load Google's pinned `@mediapipe/tasks-*` runtime from jsDelivr by
  default and check every file against its SHA-384 before running it, then
  load it from a `blob:` URL. Models download from `storage.googleapis.com`
  and are kept in Cache Storage.
- To serve the runtimes yourself (offline, an intranet, or a strict policy),
  run `dart run mediapipe_core:web_runtime web/mediapipe` from the app root
  and set `MediaPipeWebRuntime.baseUrl = 'mediapipe/';` before creating the
  first task. The same hashes apply.
- If the site sends a Content Security Policy, it has to allow what the
  loader does: `script-src` and `worker-src` for `'self'` and `blob:`,
  `'wasm-unsafe-eval'` for the WebAssembly runtime, and `connect-src` for
  `https://cdn.jsdelivr.net` (unless self-hosted) and
  `https://storage.googleapis.com` (for pinned models). CI runs without a
  policy, so test yours in the browsers you support.

## Build settings

Every setting lives under `hooks.user_defines` in the app's `pubspec.yaml`
and applies to all of the app's platforms.

| Key | Values | Effect |
| --- | --- | --- |
| `mediapipe_core.tasks_runtime` | `true` / `false` | macOS opt-in to Google's engine; `false` turns it off where it is on by default (iOS, Linux, Windows) |
| `mediapipe_core.asset_source` | directory or `http(s)` URL | Downloads every pinned runtime from there instead of its URLs; see below |
| `mediapipe_vision.tasks` | list of task names | Bundles native runtimes only for these vision tasks (default: `face_detector`, `face_landmarker`) |
| `mediapipe_vision.models`, `mediapipe_text.models`, `mediapipe_audio.models` | list of model names from `XxxModels.byName` | The models `dart run mediapipe_core:bundle_models` bundles into `assets/mediapipe/`, which the app declares under `flutter: assets:` |

### Bundling models

List the models each family uses, declare the folder, and run the command
from the app's root whenever the lists change:

```yaml
flutter:
  assets:
    - assets/mediapipe/

hooks:
  user_defines:
    mediapipe_vision:
      models: [face_landmarker, hand_landmarker]
    mediapipe_audio:
      models: [yamnet]
```

```sh
dart run mediapipe_core:bundle_models          # download, verify, prune
dart run mediapipe_core:bundle_models --check  # verify only, for CI
```

Each model is downloaded once (from `asset_source` when it is set), checked
against its pinned SHA-256 and written into `assets/mediapipe/`, named by
that SHA-256, with a readable `manifest.json` beside it. Whether to commit
the folder or run the command in CI before `flutter build` is your choice.
A task created with `model:` uses the bundled copy; a model that is not
bundled makes `create` throw a `RuntimeUnavailableException` whose `fix`
names the entry to add, unless the app set `ModelStore.allowDownloads = true`.

### Offline and mirrored builds

`asset_source` points build hooks at a directory (relative to the pubspec) or
an internal URL root holding files named by their full SHA-256. It is used
exclusively, and every file is still checked against its pin. From a checkout
of this repository, fill such a directory for your targets:

```sh
python3 -B packages/mediapipe-core/tool/mirror_runtime_assets.py \
  --target ios/arm64 --target macos/arm64 --prefill /path/to/mediapipe-assets
```

At run time, `ModelStore(source: ...)` reads models from the same kind of
source. Its cache is the one tasks created with `model:` use, keyed by SHA-256,
so prefetching through it once lets those tasks start offline:

```dart
import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';

Future<void> prefetchFromIntranet() async {
  final store = ModelStore(source: 'https://mirror.example.com/mediapipe/');
  await store.prefetch(VisionModels.faceLandmarker);
}
```
