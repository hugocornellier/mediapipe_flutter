# Platform setup

What an app needs on each platform beyond adding a family package. Google's
pinned models (`model: VisionModels.faceLandmarker` and the like) are bundled
with the app at build time by `dart run mediapipe_core:bundle_models` (see
[Build settings](#build-settings)), so an app that bundles its models needs no
network access at run time. The network settings below are only for apps
that set `ModelStore.allowDownloads = true` to download models at run time
instead.

## Android

- `minSdk` 28 (Android 9) or higher, in `android/app/build.gradle(.kts)`.
  Google's MediaPipe libraries need it, and a lower value fails the build
  with this fix.
- Each family bundles Google's MediaPipe library for that family
  (`libmediapipe_tasks_vision.so`, `libmediapipe_tasks_text.so`,
  `libmediapipe_tasks_audio.so`), so an app ships only the families it uses:
  about 13 MB for vision, 15 MB for text and 8 MB for audio on arm64-v8a. No
  Google AAR or other Gradle dependency is involved. Tasks run on arm64-v8a
  and x86_64; the armeabi-v7a library is bundled, since Flutter's release
  builds include that ABI, but no task claims it yet.
- On an emulator only the CPU is offered: it renders OpenGL ES in software
  (SwiftShader), where Google's GPU inference fails. Phones keep the GPU.
- To download models at run time, add the `INTERNET` permission to
  `android/app/src/main/AndroidManifest.xml`. Flutter adds it only to debug
  and profile builds, so a release build without it cannot download models:

  ```xml
  <uses-permission android:name="android.permission.INTERNET"/>
  ```

  When the connection fails, the `ModelDownloadException` names this
  permission.

## iOS

- iOS 15.0 or newer. Each family bundles Google's MediaPipe library for that
  family (`MediaPipeTasksVisionC`, `MediaPipeTasksTextC`,
  `MediaPipeTasksAudioC`), so an app ships only the families it uses; no
  CocoaPods or native plugin is involved. The build extracts only the device
  or simulator slice it needs.
- On the iOS Simulator only the CPU is offered: Google's MediaPipe aborts on
  the simulator's GPU path. Devices keep Metal.
- Downloaded models live in the app's Application Support folder, excluded
  from iCloud backup.

## macOS

- macOS 14.0 or newer on Apple Silicon.
- Build the app for Apple Silicon only. Flutter's release and profile builds
  (`flutter build macos`, `flutter run --release`) also build an Intel
  (x86_64) slice by default, and Google's MediaPipe libraries have none, so
  such a build fails with these instructions. Add these lines to
  `macos/Runner/Configs/AppInfo.xcconfig`:

  ```text
  ARCHS = arm64
  EXCLUDED_ARCHS = x86_64
  ```

  Or run `flutter config --enable-macos-arm64-only`, which does the same for
  every app that machine builds, CI runners included. Debug builds target
  only the Mac they run on, so they work either way. Setting the Runner's
  deployment target (`MACOSX_DEPLOYMENT_TARGET`) to 14.0 also keeps the app
  off older macOS, where the libraries cannot load.
- Each family bundles Google's MediaPipe library for that family: about
  27 MB for vision, 26 MB for text and 13 MB for audio.
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
  load it from a `blob:` URL. Bundled models load from the app's own assets.
  Models downloaded at run time (`ModelStore.allowDownloads = true`) come from
  `storage.googleapis.com` and are kept in Cache Storage.
- To serve the runtimes yourself (offline, an intranet, or a strict policy),
  run `dart run mediapipe_core:web_runtime web/mediapipe` from the app root
  and set `MediaPipeWebRuntime.baseUrl = 'mediapipe/';` before creating the
  first task. The same hashes apply.
- If the site sends a Content Security Policy, it has to allow what the
  loader does: `script-src` and `worker-src` for `'self'` and `blob:`,
  `'wasm-unsafe-eval'` for the WebAssembly runtime, and `connect-src` for
  `'self'` (bundled models), `https://cdn.jsdelivr.net` (unless self-hosted)
  and `https://storage.googleapis.com` (only for models downloaded at run
  time). CI runs without a policy, so test yours in the browsers you support.

## Build settings

Every setting lives under `hooks.user_defines` in the app's `pubspec.yaml`
and applies to all of the app's platforms.

| Key | Values | Effect |
| --- | --- | --- |
| `mediapipe_core.asset_source` | directory or `http(s)` URL | Downloads every pinned runtime from there instead of its URLs; see below |
| `mediapipe_vision.tasks` | list of task names | Checks the names against the tasks validated on the target (a Windows build fails on `interactive_segmenter`) |
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
