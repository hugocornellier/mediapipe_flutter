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
python3 -B packages/mediapipe-core/tool/test_bundled_models.py
```

The last one builds fresh apps from the packages as pub.dev would ship them:
it bundles one model per family with `dart run mediapipe_core:bundle_models`
and runs them offline. CI runs the
rest (Android emulator, Linux, Windows and three browsers).

## Versions and the first release

Nothing from this repository is on pub.dev yet. The first release will be
0.1.0 of `mediapipe_core`, `mediapipe_vision`, `mediapipe_text` and
`mediapipe_audio`, published together.

On pub.dev, `mediapipe_core` and `mediapipe_text` (and the removed
`mediapipe_genai`) are Google's 0.0.1 previews from May 2024, published from
[google/flutter-mediapipe](https://github.com/google/flutter-mediapipe).
Only their uploaders can publish new versions of these names, and the next
version must be above 0.0.1. Under Dart's rules for versions before 1.0, the minor version
marks a breaking change, so 0.1.0 is the version that follows Google's
previews. `mediapipe_vision` and `mediapipe_audio` are free names, kept at
0.1.0 so all four release together.

Until the first release:

- Every package stays at `version: 0.1.0` with `publish_to: none`, however
  much changes.
- Each CHANGELOG has one section, `## 0.1.0 (unreleased)`, describing the
  package as it will ship. Edit that section; do not add version sections,
  and do not call a change breaking or list what it renamed, since no
  release came before it.
- `MIGRATION.md` covers only Google's published 0.0.1 API. Changes between
  unpublished states never need a migration note.

At the first release, remove `publish_to: none` and the `(unreleased)` marks
in one commit, then run `publish_check.py` and the bundled-model check above.

## How to add a task

A task is only complete when it runs Google's official pipeline on every
platform it claims, and a test proves the output matches Google's.

1. **Pin the model.** Add Google's model URL and SHA-256 to the family's
   `lib/models.dart` (`XxxModels.name`), and its snake_case name to
   `XxxModels.byName` so apps can bundle it. `mirror_runtime_assets.py` picks
   it up; give it a license there if it is not Apache-2.0.
2. **Native platforms.** Bind Google's C API with the family's `ffigen` config
   and wrap it in `lib/src/io/`: create, run and close on a worker isolate,
   copying results into the shared value types from `mediapipe_core`
   (`MediaPipeCategory`, `Classifications`, `Landmark` and so on). On iOS, where Google ships only an
   Objective-C SDK, add the same C functions to core's adapter in
   `packages/mediapipe-core/native/ios/`.
3. **Android.** Add the task to the family's Java plugin (Google's Android
   SDK) and its Dart backend in `lib/mediapipe_<family>_android.dart`. The
   backend only reshapes the plugin's reply into Google's JavaScript result
   shape; the family's one decoder (`lib/src/results/decoders.dart` in
   vision and text, `lib/src/decoders.dart` in audio) reads it, for Android
   and the web alike.
4. **Web.** Add it to the family's `assets/worker.js`, using Google's bundle,
   and to the Dart web backend, which hands the worker's JSON to the same
   decoder.
5. **Capabilities.** Declare where it runs and why not elsewhere in the
   family's `lib/src/capabilities.dart`: `queryXxxCapabilities()` and a pure
   `xxxCapabilitiesForPlatform(TaskPlatform)`. For vision, also add it to the hook's task
   lists (`officialAndroidTasks`, `officialIosTasks`, `macosEngineTasks`) and
   to `tool/VISION_TASKS_STATUS.md` in the same commit.
6. **Public API.** One class for every platform. `XxxOptions` extends core's
   `TaskOptions` (`model`, `modelPath`, `modelBytes`, `delegate`) with
   Google's settings and defaults; `static Future<Xxx> create(XxxOptions)`
   refuses a delegate the capability query rules out (core's
   `requireDelegate`); Google's verb (`detect`, `classify`, `embed` and so
   on); an immutable `XxxResult` on the shared value types; a `delegate`
   getter; an idempotent `Future<void> dispose()`; failures as
   `TaskException`, errors through the returned `Future`. Export it from the
   family's main library and run `tool/api_parity`
   (`dart run bin/api_parity.dart --update`) so the snapshot shows the new
   API; the check requires it to be identical on native and web.
7. **Tests.** Generate a reference with Google's own Python for the pinned
   runtime version, check it in as a fixture, and compare every value in unit
   tests; add the task to the browser suite's comparison with Google's
   JavaScript and to the CI coverage rows (`tool/coverage/`). A task whose
   output differs between Google's releases (the generative text tasks) is
   compared with the wheel of each platform's own version, generated on the
   runner (`packages/mediapipe-task-text/tool/prepare_modern_text_reference.py`).
8. **Docs.** The family README's task table, the CHANGELOG, and any platform
   limit with its upstream issue in `upstream-issues.md`.
