## 0.2.0

- Google's MediaPipe 1.2.2 native release (build of November 2, 2026)
  replaces 1.2.0 on Android, iOS, macOS, Linux and Windows, and
  `@mediapipe/tasks-*` 1.2.2 replaces 1.2.0-rc.20261018 in browsers.
- Binds the 1.2.2 retrieval C API: Semantic Retriever options now lead with
  Google's base options, which the retriever fills as the other tasks do, so
  Google's usage log records the host for it too (UP-063). Universal
  Embedder takes Google's per-modality delegate fields, left at their
  default.
- Ships Google's `NOTICE` at the package root, beside `LICENSE`.

## 0.1.0

The first release.

- Universal Embedder and Semantic Retriever on Android, iOS, macOS, Linux,
  Windows and the web, through Google's official MediaPipe runtimes: its
  per-family 1.2.0 retrieval C library natively and `@mediapipe/tasks-retrieval`
  in browsers.
- Universal Embedder and Semantic Retriever need 64-bit Android: 32-bit
  (armeabi-v7a) cannot hold their models, and their capability queries say
  so.
- `UniversalEmbedder` embeds text, encoded images and audio samples into one
  space, with `cosineSimilarity`; `SemanticRetriever` indexes documents,
  images, audio and mixed content with metadata and retrieves the nearest
  records, with the same results on every platform.
- `RetrievalModels` pins Google's EmbeddingGemma 2 models.
- Neither task is offered in WebKit, where Google's browser runtime returns
  zeros for every input with both models (UP-054).
