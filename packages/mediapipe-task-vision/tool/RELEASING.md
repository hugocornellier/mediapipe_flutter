# Native runtime releases

The Dart/Flutter source repository is private. Public native downloads live in
[`hugocornellier/mediapipe_flutter_native`](https://github.com/hugocornellier/mediapipe_flutter_native),
whose Git history contains the native-runtime README. Releases contain the
compiled upstream runtime, manifest, and checksums. Do not push this private
repository's Git history, package code, model files, or test fixtures there.

## Prepare and test

1. Choose a new release tag for every rebuild, even when upstream versions are
   unchanged. Update the task's entry in `RELEASE_TAGS` in
   `prepare_native_release.py`; consumer tests read the same expected tags.
   Initial releases are `face-detector-v1.0.0-1` and `face-landmarker-v1.0.0-1`.
   The `-2` releases add CPU and Metal in each task library. Release builds must
   pass both native smoke modes on a Metal-capable Mac; the builder checks the
   delegate creation log and Objective-C class namespace before packaging.
2. Run the pinned source build and native/inference tests (`make ci` from the
   repository root). This tests the local source build; it does not publish it.
3. Run `python3 tool/prepare_native_release.py` from this package directory.
   For the mesh runtime, add `--task face_landmarker` to both the source builder
   and release preparation command.
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
   private wrapper source, models, fixtures or local validation logs.
5. Run `python3 -B tool/test_segmenter_macos.py` against the public URL. Commit
   the resulting validation/benchmark report and keep existing release assets
   immutable. A rebuild requires a new tag and updated pins in
   `sdk_downloads.dart` and `interactive_segmenter_library.dart`.
