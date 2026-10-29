#!/bin/sh
# Copies Google's pinned, verified browser runtimes into the release gallery
# build, which loads them from its own origin when built with
# --dart-define=MEDIAPIPE_WEB_RUNTIME=mediapipe/ (see lib/main.dart). Only the
# module builds stay: the loader asks for those in every browser, never the
# SIMD and no-SIMD ones (packages/mediapipe-core/tool/ASSET_HOSTING.md).
# Run from gallery/ after `flutter build web`.
set -eu
dart run mediapipe_core:web_runtime build/web/mediapipe
find build/web/mediapipe \( -name '*_wasm_internal.*' -o -name '*_nosimd_internal.*' \) -delete
