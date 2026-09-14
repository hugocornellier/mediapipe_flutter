import 'package:mediapipe_flutter_core/native_assets.dart';

/// Google's unmodified EmbeddingGemma 300M task, mixed int4/int8, version 1.
/// Maximum sequence length: 512 tokens, including prompt and special tokens.
const DownloadAsset embeddingGemmaModel = (
  url:
      'https://storage.googleapis.com/mediapipe-models/text_embedder/'
      'embedding_gemma/int4int8/1/embedding_gemma.task',
  sha256: '913b7a1edc7c7c3d1da3979ec1d0648ed9e0a370f181bb59ab177ca4b97707ad',
);

/// Google's unmodified Proofread 200M mixed int4/int8 model, version 1.
const DownloadAsset proofreaderModel = (
  url:
      'https://storage.googleapis.com/mediapipe-models/text_proofreader/'
      '200m/1/proofread_quant_200m.litertlm',
  sha256: '2caa317d5a6f951af6e437edce3bb3a9fdedc85a7a8c2a8fcaec96318d7708cc',
);
