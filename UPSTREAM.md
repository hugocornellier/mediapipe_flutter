# Upstream provenance

- Source: https://github.com/google/flutter-mediapipe
- Branch: `main`
- Fork base: `d3e554eacc81bc469fad525f54ed533b2fc585e7`
- Private repository: https://github.com/hugocornellier/mediapipe_flutter

This is a standalone private repository containing the upstream Git history.
GitHub does not permit a private fork of a public repository within its fork
network. The local `upstream` remote tracks Google's original repository;
`origin` points to this private repository.

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

The root marker used by the build tooling is `.mediapipe_flutter-root`.

## Tracking upstream

```sh
git fetch upstream
git log --oneline HEAD..upstream/main
```

Review incoming changes before merging them because package identities differ.
The initial fork and rename do not add task implementations or replace native
SDKs. Use the upstream revision above when comparing inherited behavior.

## Initial validation

Checked with Dart 3.12.2 on macOS arm64:

- Core package: all 30 existing tests pass; analysis passes.
- Text package library and build tool: analysis passes.
- Core, text, and GenAI package dependencies resolve to this checkout's renamed
  core package. The GenAI example separately fails dependency resolution because
  its inherited `intl: ^0.19.0` conflicts with current Flutter's `intl: 0.20.2` pin.
- GenAI library analysis reports three inherited `annotate_overrides` notices.
- All 139 Dart source files were compared with the upstream base: only the
  intended identity substitutions, the GenAI library-name correction, and
  trailing whitespace differ.
- `LICENSE` and `AUTHORS` are byte-for-byte identical to the upstream versions.

Native inference and the unfinished vision scaffold were not validated by this
rename. Their implementation and runtime modernization remain separate work.
