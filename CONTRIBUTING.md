# Contributing to mediapipe_flutter

This is an independent development fork maintained at
https://github.com/hugocornellier/mediapipe_flutter.

Open issues and pull requests in this repository. Describe the problem, the
resulting behavior, and relevant validation. Keep runtime updates and new task
implementations separate from mechanical package renames where practical.

Retain existing copyright and license notices. Include the appropriate license
notice in new source files and follow the surrounding Dart or native code style.
Run the checks relevant to the affected package and document any native SDK or
device requirements that prevent validation.

This fork does not use Google's contributor agreement or internal review process.
Contributions sent separately to the original Google repository must follow that
repository's own contribution requirements.

See [README.md](README.md) for the current development scope and
[UPSTREAM.md](UPSTREAM.md) for provenance.

## Before opening a pull request

From the repository root, run what applies to your change:

```sh
make check_format
make test                      # analysis and every package's unit tests
python3 -B tool/check_docs.py  # README samples compile, links resolve
python3 -B packages/mediapipe-core/tool/publish_check.py   # pub dry run
python3 -B packages/mediapipe-core/tool/test_family_consumers.py --platform macos
```

The last one builds fresh apps from the packages as pub.dev would ship them;
it has an `--platform ios-simulator --device <uuid>` form too. CI runs the
rest (Android emulator, Linux, Windows and three browsers).

## How to add a task

A task is only complete when it runs Google's official pipeline on every
platform it claims, and a test proves the output matches Google's.

1. **Pin the model.** Add Google's model URL and SHA-256 to the family's
   `lib/models.dart` (`XxxModels.name`). `mirror_runtime_assets.py` picks it
   up; give it a license there if it is not Apache-2.0.
2. **Native platforms.** Bind Google's C API with the family's `ffigen` config
   and wrap it in `lib/src/io/`: create, run and close on a worker isolate,
   copying results into owned Dart types. On iOS, where Google ships only an
   Objective-C SDK, add the same C functions to core's adapter in
   `packages/mediapipe-core/native/ios/`.
3. **Android.** Add the task to the family's Java plugin (Google's Android
   SDK) and its Dart backend in `lib/mediapipe_<family>_android.dart`.
4. **Web.** Add it to the family's `assets/worker.js`, using Google's bundle,
   and to the Dart web backend.
5. **Capabilities.** Declare where it runs and why not elsewhere in the
   family's `capabilities.dart`. For vision, also add it to the hook's task
   lists (`officialAndroidTasks`, `officialIosTasks`, `macosEngineTasks`) and
   to `tool/VISION_TASKS_STATUS.md` in the same commit.
6. **Public API.** `XxxOptions` taking `model:`, `modelPath` or `modelBytes`;
   `static Future<Xxx> create(XxxOptions)`; an `XxxResult`; an idempotent
   `dispose()`; failures as the family's `MediaPipeException` subtype. Export
   it from the family's main library and record it in `tool/API_REVIEW.md`.
7. **Tests.** Generate a reference with Google's own Python for the pinned
   runtime version, check it in as a fixture, and compare every value in unit
   tests; add the task to `test_family_consumers.py`, to the browser suite's
   comparison with Google's JavaScript, and to the CI coverage rows
   (`tool/coverage/`).
8. **Docs.** The family README's task table, the CHANGELOG, and any platform
   limit with its upstream issue in `upstream-issues.md`.
