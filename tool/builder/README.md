# MediaPipe maintainer tools

Use the repository baseline: Flutter 3.44.8 / Dart 3.12.2.
Run `dart pub get` in this directory before using the tool.

## Test models

From the repository root, `make models` downloads the three text models into the
text example's ignored `assets/` directory. Standard downloads use explicit
version-1 URLs and SHA-256 checks, reuse valid cached files, and replace files
only after the download is complete and verified.

The optional `model --custommodel <URL> --destination <directory>` command retains
its legacy unverified download behavior. Custom models are not used by CI.

## Headers and native runtimes

`make generate` regenerates header-based bindings and checks the text 1.0.1 ABI
against its pinned Python ctypes fixture. It does not require a separate
MediaPipe checkout. The retired text headers are no longer imported/generated.

`make headers` imports headers from a local `google/mediapipe` checkout. Only use
this as part of a coordinated native runtime update: headers, ABI, binary URLs,
and SHA-256 digests must match. Importing current headers alone can break FFI.

`make sdks` uses the inherited Google bucket-discovery machinery, which requires
`gsutil` and access to list Google's build bucket. It writes
`sdk_downloads.candidate.dart` files for review, not active manifests. Normal
builds and tests do not need this command or Google credentials.

The bucket-discovery tool is inherited; its candidates do not drive modern text
or vision builds. Text uses the shared official 1.0.1 archive, and vision uses
public pinned releases. Only GenAI still uses the 2024 runtime.
