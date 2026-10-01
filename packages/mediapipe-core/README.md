# mediapipe_core

The shared layer of the MediaPipe task packages (`mediapipe_vision`,
`mediapipe_text`, `mediapipe_audio`); apps normally get it through them rather
than depending on it directly. It owns everything the
task families share, so each of vision, text and audio works alone and an app
using several loads one copy of each shared piece. That includes Google's
verified MediaPipe engine, which every family binds:

| Platform | Engine | Setting |
| --- | --- | --- |
| iOS (device, arm64 simulator) | an adapter core builds over Google's 1.0.1 iOS SDK | on by default |
| Linux x64 | the official 1.0.1 wheel's library | on by default |
| Windows x64 | the official 1.0.0 wheel's library | on by default |
| macOS 14+ arm64 | the official 1.0.0 wheel's library (about 95 MB) | opt-in |
| Android, web | Google's own SDKs, through each family's plugin | none |

On macOS, text, audio and every vision task except Face Detector and Face
Landmarker need the engine, so the app opts in:

```yaml
hooks:
  user_defines:
    mediapipe_core:
      tasks_runtime: true
```

Without it a macOS build still succeeds, so `dart run` keeps working in an
app that only ships iOS or Android. Capability queries then report those tasks
unavailable, and creating one throws an `UnsupportedError` with this fix.
`tasks_runtime: false` turns the engine off where it is on by default; a
family that needs it there fails the build with the fix instead.

## Verified downloads and offline builds

Every native runtime and model pin names a primary URL, optional published
mirrors, and one SHA-256. Core tries URLs in order and checks the digest before
publishing a file. It reports every failed location when none matches. Pins
do not currently name mirrors because no alternate copies have been published.

For offline or mirrored builds, point every download at a local directory or
an internal HTTP(S) root holding files named by their full SHA-256. That
source is then used exclusively: the digest check still applies, and a
missing or wrong file fails the build rather than falling back to the
internet.

- Build hooks read it from the app's pubspec (a relative directory resolves
  against that pubspec):

  ```yaml
  hooks:
    user_defines:
      mediapipe_core:
        asset_source: third_party/mediapipe-assets
  ```

  Hooks cannot use an environment variable here: Dart's hook runner passes
  them only an allowlist of variables.
- `ModelStore(source: ...)` takes the same kind of source at run time.
- Command-line tools (`dart run`) read the `MEDIAPIPE_ASSET_SOURCE`
  environment variable.

From a checkout of this repository, fill such a directory for the build
targets you need. Models are included for every target, since apps may use
any family:

```sh
python3 -B packages/mediapipe-core/tool/mirror_runtime_assets.py \
  --target macos/arm64 --target ios/arm64 --prefill /path/to/mediapipe-assets
```

The same tool without `--prefill` is a dry run inventory. It lists each pin,
its target, license information when known, and a proposed GitHub release
asset name. It never uploads anything. The prefill path uses core's verified
downloader. Copy the resulting SHA-named directory to the build machine, or
serve it from an internal URL root.

## Bundled models

Apps bundle the models they use at build time. Each family's `XxxModels.byName`
names its models. The app lists the ones it needs per family in its pubspec,
declares `assets/mediapipe/` under `flutter: assets:`, and runs from its root:

```sh
dart run mediapipe_core:bundle_models
```

The command downloads each listed model (from `asset_source` when it is set),
checks it against its pinned SHA-256, and writes it into `assets/mediapipe/`,
named by that SHA-256 with a readable `manifest.json` beside it. Models that
are no longer listed are removed. With `--check` it changes nothing and fails
when the folder does not match the lists, for CI. It reads each family's
models by running a small generated program,
`.dart_tool/mediapipe_core/bundle_models_registry.dart`, with the app's
packages, since core cannot depend on the families.

A task created with `model:` then looks for its model in this order:

1. the store's cache;
2. the app's bundled copy, copied into the cache once on native platforms,
   where MediaPipe takes a file path;
3. a download, only when `ModelStore.allowDownloads` is true.

Otherwise `create` throws a `RuntimeUnavailableException` whose `fix` names
the pubspec entry to add. `ModelStore().find(model)` performs the same lookup
without ever using the network.

## On-demand models

Downloading at run time is opt-in. Set `ModelStore.allowDownloads = true`
before creating tasks to let `model:` download what the app does not bundle;
calling `get` or `prefetch` directly always may download.

`package:mediapipe_core/model_store.dart` exports `ModelStore` and
`DownloadAsset`. A family model pin can be passed directly to `get` or
`prefetch`; `clear` removes the store's entries. On native platforms `get`
returns a `File` in application support, whose path can be given to the task
options. Each model keeps its original file name. Downloads go to an adjacent
temporary file under a per-model lock shared across isolates and processes,
and cached bytes are checked again on every read. iOS excludes this model folder
from iCloud backup. On web `get` returns verified bytes from Cache Storage
or the app's bundle, and otherwise downloads them. An invalid cached
response is discarded.
Core uses Flutter's `path_provider` for application support rather than
asking every family to supply a directory, so the storage policy stays shared.

```dart
import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_text/mediapipe_text.dart';

Future<void> prepareModels() async {
  final store = ModelStore();
  await store.prefetch(TextModels.bertClassifier);
  final file = await store.get(TextModels.bertClassifier); // native: a File
  print(file.path);
}
```

Downloading needs Android's `INTERNET` permission, and a sandboxed macOS app
needs `com.apple.security.network.client`. Bundled models and already
verified cache entries work without network access.

## Web runtime

Browsers load Google's pinned MediaPipe JavaScript and WASM runtime for each
task family (vision, text, audio) from jsDelivr. One setting moves all of them.
For offline use or a strict Content Security Policy, copy the verified
runtimes of the families your app uses into its `web/` folder, from the app
root:

```sh
dart run mediapipe_core:web_runtime web/mediapipe
```

The tool downloads each family's pinned npm archive, checks its integrity and
each listed file's SHA-384, and writes only the files the browser loads.
Workers verify those same file digests from any configured root before
loading the bundle and WASM through Blob URLs. Then, before creating the
first task:

```dart
import 'package:mediapipe_core/web_runtime.dart';

void useSelfHostedRuntime() {
  MediaPipeWebRuntime.baseUrl = 'mediapipe/';
}
```

`baseUrl` is an npm-style root, so another npm CDN such as
`https://unpkg.com/` works as well. Each family's
`package:mediapipe_<family>/web_runtime.dart` exports the same class.
Serve the files with CORS and CSP rules appropriate to your origin.

## Issues and feedback

Please file issues, bugs, or feature requests in our [issue tracker](https://github.com/hugocornellier/mediapipe_flutter/issues/new).

Issues that are specific to Flutter can be filed in the [Flutter issue tracker](https://github.com/flutter/flutter/issues/new).

To contribute a change to this plugin,
please review our [contribution guide](https://github.com/hugocornellier/mediapipe_flutter/blob/main/CONTRIBUTING.md)
and open a [pull request](https://github.com/hugocornellier/mediapipe_flutter/pulls).
