# Official EmbeddingGemma reference

`official_reference.json` contains outputs from Google's unmodified MediaPipe
1.0.1 macOS arm64 wheel, CPU delegate, and the version 1 EmbeddingGemma 300M task.
The JSON records the exact native-library/model SHA-256 digests and ctypes ABI.
Prompts are passed as `TextFormatContext` to Google, not formatted by this repo.
All input sentences were written for this test; no external text corpus is used.

Regenerate with `tool/generate_embedding_gemma_reference.py` using the pinned
1.0.1 wheel (see the vision package's runtime preparation tool). The script
checks its version, architecture and native checksum before inference.
Do not replace these references with Dart-generated outputs.

The model is downloaded separately by `dart tool/download_embedding_gemma.dart`;
it is not committed. Its terms are Google's
[Gemma Terms](https://ai.google.dev/gemma/terms).
