# MediaPipe browser text tasks

Flutter web adapter that runs Text Classifier, Text Embedder and Language Detector from `mediapipe_flutter_text` on
Google's unmodified **@mediapipe/tasks-text 1.0.1** JavaScript/WASM
distribution, one worker per task. Add this package next to
`mediapipe_flutter_text` in a Flutter web app; the public API is the same
as on native platforms. Without it, creating a task in a browser throws an
`UnsupportedError` that names this package.

Tasks run on CPU. Google's browser text tasks accept the GPU delegate but
return bit-identical results, because the text WASM build has no GPU
inference path, so the API does not offer it.

`tool/prepare_runtime.py` downloads the npm tarball, checks its pinned
SHA-512 integrity and writes the files it extracts, with their SHA-256
digests, to `assets/runtime/provenance.json`. The gallery's
`tool/prepare.py --target web` runs it.

CI (`.github/workflows/web.yaml`, suite `text-audio`) compares every
number the Dart API returns with Google's JavaScript on the same page and
inputs in Chromium, Firefox and WebKit. In Chromium, it also classifies a
speech clip played through the fake microphone.
