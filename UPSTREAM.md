# Upstream provenance

- Source: https://github.com/google/flutter-mediapipe
- Branch: `main`
- Fork base: `d3e554eacc81bc469fad525f54ed533b2fc585e7`
- Repository: https://github.com/hugocornellier/mediapipe_flutter

This standalone repository contains the upstream Git history. It was created
privately, outside GitHub's fork network, and made public on 2026-09-12.
The local `upstream` remote tracks Google's original repository;
`origin` points to this maintained repository.

## Initial rename

| Upstream package | Fork package |
| --- | --- |
| `mediapipe_core` | `mediapipe_flutter_core` |
| `mediapipe_text` | `mediapipe_flutter_text` |
| `mediapipe_genai` | `mediapipe_flutter_genai` |
| `mediapipe_vision` | `mediapipe_flutter_vision` |

Dart imports, library entry points, generated-binding paths, build-hook asset
identities, documentation, and local dependencies follow the renamed packages.
Native MediaPipe symbols, SDK download URLs, and upstream license notices retain
their original identity. Existing package versions are preserved at this stage.

## Google's names restored

On 2026-09-30 the packages took Google's names again (`mediapipe_core`,
`mediapipe_vision`, `mediapipe_text`, `mediapipe_genai`, plus the new
`mediapipe_audio`), since this code is meant to replace Google's packages, and
took version 0.1.0, the first release after Google's 0.0.1 previews (not
published yet; see CONTRIBUTING.md). Directory names (`packages/mediapipe-core`,
`packages/mediapipe-task-*`) are unchanged. The `mediapipe_flutter_native`
release host keeps its name, and validation evidence keeps the names it was
recorded with.

The root marker used by the build tooling is `.mediapipe_flutter-root`.

## `mediapipe_genai` removed

On 2026-10-05 `mediapipe_genai` was removed, with the FFI-era API in core
(`io.dart`, `interface.dart`) that only it used. It had stayed on Google's 2024
runtime and never adopted the shared API. Both remain in git history at
`4b37b72`.

## Tracking upstream

```sh
git fetch upstream
git log --oneline HEAD..upstream/main
```

Review incoming changes before merging them because package identities differ.
The initial fork and rename do not add task implementations or replace native
SDKs. Use the upstream revision above when comparing inherited behavior.
