/// Official EmbeddingGemma text embeddings, currently macOS arm64 CPU.
library;

export 'capabilities.dart';
export 'src/interface/embedding_gemma_types.dart';
export 'src/interface/embedding_gemma_stub.dart'
    if (dart.library.io) 'src/io/embedding_gemma.dart';
