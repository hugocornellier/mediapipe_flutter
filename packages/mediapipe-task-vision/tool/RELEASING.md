# Native runtime releases

The Dart/Flutter source repository is public. Native downloads live separately in
[`hugocornellier/mediapipe_flutter_native`](https://github.com/hugocornellier/mediapipe_flutter_native),
whose Git history contains the native-runtime README. Releases contain the
compiled upstream runtime, manifest, and checksums. Do not push this source
repository's Git history, package code, model files, or test fixtures there.

## Prepare and test

1. Choose a new release tag for every rebuild, even when upstream versions are
   unchanged, and set it as `TAG` in `prepare_native_release.py`. `RELEASE_TAGS`
   in the same file is a separate list: the releases `sdk_downloads.dart`
   actually pins, which consumer tests assert the hook extracted. Move a tag
   into `RELEASE_TAGS` only once it is published and pinned, never before.
   `vision-v1.0.0-1` is the first combined runtime; it supersedes
   `face-detector-v1.0.0-2` and `face-landmarker-v1.0.0-2`, which stay pinned
   until it is published. Release builds must pass every native smoke mode on a
   Metal-capable Mac; the builder checks the delegate creation log and the
   Objective-C class namespace before packaging.
2. Run the pinned source build and native/inference tests (`make ci` from the
   repository root). This tests the local source build; it does not publish it.
3. Run `python3 tool/prepare_native_release.py` from this package directory.
   One invocation covers every task: the source builder links
   `//mediapipe/tasks/c:libmediapipe`, so a single `libmediapipe.dylib` exports
   all 11 vision tasks, the 3 classic text tasks and the audio classifier.
   Inspect the generated archive, `manifest.json`, `SHA256SUMS`, README, and
   release notes under `build/releases/<tag>/`. The preparation step removes
   local paths from the manifest and normalizes tar/gzip timestamps and owners.
4. Pin the generated archive URL, archive SHA-256, and library SHA-256 in
   `sdk_downloads.dart`. Keep the runtime's original C API and upstream source
   provenance aligned with its bindings and integration references.
5. Run `python3 tool/test_prebuilt_macos.py --local-release build/releases/<tag>`.
   This serves the exact candidate over loopback HTTP and changes only the URL
   in a temporary package copy; the digests remain pinned. The other task's
   archive is downloaded from its public URL. Both Flutter debug
   and release apps must perform real inference with native build tools blocked.
   When updating both tasks together, copy both prepared archives into one
   candidate directory and pass that directory to `--local-release`.

## Publish

Create the release in the **public native repository**, using the prepared
`RELEASE_NOTES.md` via `gh release create --notes-file`. Upload exactly:

- `mediapipe-face-detector-1.0.0-macos-arm64.tar.gz` or
  `mediapipe-face-landmarker-1.0.0-macos-arm64.tar.gz`, for the selected task
- `SHA256SUMS`
- `manifest.json`

The archive contains the library plus MediaPipe/OpenCV licenses and notices.
Keep source and model files separate. Published download URLs are immutable by
convention: do not replace or delete assets that an existing package pins.

Run `python3 tool/test_prebuilt_macos.py` without the local mirror option after
publication. It must pass against the public GitHub URL with no credentials.
Commit the reviewed pins and documentation on the feature branch.

CI has two independent paths: the full native source build and a fresh consumer
of the published archive. CI artifacts from a source build are review candidates;
uploading a CI artifact does not automatically publish a GitHub Release.

## Interactive Segmenter

This task uses the full pinned official 1.0.1 macOS wheel runtime because its
modern stateful C API is not available in the public source build. See
[the provenance and API guide](INTERACTIVE_SEGMENTER.md).

1. Run `python3 -B tool/prepare_interactive_segmenter.py`. It verifies the wheel,
   extracts the runtime and complete upstream notices, adjusts only loader and
   signing metadata, and verifies unchanged native code/data.
2. Review the generated archive, manifest, checksums and release notes in
   `build/releases/interactive-segmenter-v1.0.1-1/`. Keep the original upstream
   digests separate from prepared artifact digests.
3. Run the Dart reference and artifact tests, the editor tests, and
   `python3 -B tool/test_segmenter_macos.py --local-release build/releases/interactive-segmenter-v1.0.1-1`.
4. Publish the tar.gz, `SHA256SUMS` and `manifest.json` to a new prerelease in the
   public native repository using the generated notes. Do not upload the wheel,
   wrapper source, models, fixtures or local validation logs.
5. Run `python3 -B tool/test_segmenter_macos.py` against the public URL. Commit
   the resulting validation/benchmark report and keep existing release assets
   immutable. A rebuild requires a new tag and an updated row in core's
   `tasks_runtime.dart` release table.

## Runtime tables and release layout

Build hooks are table-driven. Each hook computes a build target such as
`macos/arm64`, `ios-simulator/arm64`, `linux/x64` or `windows/arm64`
(`buildTarget` in core's `native_assets.dart`) and looks it up:

- `packages/mediapipe-core/lib/src/native_assets/tasks_runtime.dart` maps a
  target to one `TasksRuntimeRelease` row: the shared official 1.0.1 runtime's
  archive, library digests, minimum OS, delegates and provenance. Text tasks
  and MagicTouch are served from this runtime.
- `packages/mediapipe-task-vision/sdk_downloads.dart` lists
  `VisionRuntimeRelease` rows: a source-built archive per target with the set
  of tasks it exports. The hook downloads each release that covers a selected
  task once and refuses selected tasks that no row on the target provides.

Supporting a new platform means publishing an archive and adding a row; the
hooks, consumer tests and asset names need no changes. Targets without a row
fail the build with a message naming the published targets. The runtime-side
support claim (`TaskCapabilities` and `tasksRuntimeTargets` in core's
`capabilities.dart`) is kept in step with the build-side table so a platform is
never reported supported without a runtime, or bundled without a support claim.

Archives are named per (runtime family, platform, architecture), one release
tag per family build:

| Family | Tag | Archive |
| --- | --- | --- |
| Shared official 1.0.1 runtime (macOS, historical) | `interactive-segmenter-v1.0.1-1` | `mediapipe-interactive-segmenter-1.0.1-macos-arm64.tar.gz` |
| Shared official 1.0.1 runtime (all other targets) | `tasks-v1.0.1-<build>` | `mediapipe-tasks-1.0.1-<platform>-<arch>.tar.gz` |
| Source-built v1.0.0 tasks | `<family>-v1.0.0-<build>` | `mediapipe-<family>-1.0.0-<platform>-<arch>.tar.gz` |

`python3 -B tool/prepare_interactive_segmenter.py --target <platform>/<arch>`
prepares the shared runtime for any target Google publishes a wheel for
(`macos/arm64`, `linux/x64`, `linux/arm64`, `windows/x64`, `windows/arm64`).
The macOS row reproduces the published archive byte-for-byte. Other targets
ship the wheel's library unchanged and record `platform`/`architecture` with
Dart's names so they match the release table's target key. Candidates land in
`build/releases/<tag>/` with one manifest per target, a combined `SHA256SUMS`
and per-archive release notes. Linux libraries need `libEGL.so.1` and
`libGLESv2.so.2` on the host even for CPU inference; the Windows wheels do not
ship MagicTouch. Publishing a candidate and adding its table row is a separate,
validated step per platform.
