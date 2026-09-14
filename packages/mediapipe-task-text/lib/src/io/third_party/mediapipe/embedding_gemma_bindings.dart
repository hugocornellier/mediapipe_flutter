// Copyright 2026 The MediaPipe Authors. Licensed under Apache 2.0.
// Adapted from mediapipe==1.0.1 Python ctypes: text/text_embedder.py,
// core/base_options_c.py, components/containers/embedding_result_c.py.
// Sizes and field offsets are checked against the pinned official definitions.
// ignore_for_file: public_member_api_docs
import 'dart:ffi';

const _asset = 'package:mediapipe_flutter_core/tasks_1_0_1.dylib';

final class MpBaseOptions extends Struct {
  external Pointer<Char> modelAssetBuffer;
  @Uint32()
  external int modelAssetBufferCount;
  external Pointer<Char> modelAssetPath;
  @Int32()
  external int fileDescriptor;
  @Int32()
  external int delegate;
  @Int32()
  external int hostEnvironment;
  @Int32()
  external int hostSystem;
  external Pointer<Char> hostVersion;
  external Pointer<Char> caBundlePath;
  external Pointer<Char> appId;
  external Pointer<Char> appVersion;
}

final class MpEmbedderOptions extends Struct {
  @Bool()
  external bool l2Normalize;
  @Bool()
  external bool quantize;
}

final class MpTextEmbedderOptions extends Struct {
  external MpBaseOptions baseOptions;
  external MpEmbedderOptions embedderOptions;
}

final class MpTextFormatContext extends Struct {
  @Int32()
  external int taskType;
  external Pointer<Char> title;
  @Int32()
  external int role;
}

final class MpEmbedding extends Struct {
  external Pointer<Float> floatEmbedding;
  external Pointer<Uint8> quantizedEmbedding;
  @Uint32()
  external int valuesCount;
  @Int32()
  external int headIndex;
  external Pointer<Char> headName;
}

final class MpEmbeddingResult extends Struct {
  external Pointer<MpEmbedding> embeddings;
  @Uint32()
  external int embeddingsCount;
  @Bool()
  external bool hasTimestampMs;
  @Int64()
  external int timestampMs;
}

@Native<
  Int32 Function(
    Pointer<MpTextEmbedderOptions>,
    Pointer<Pointer<Void>>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpTextEmbedderCreate', assetId: _asset)
external int create(
  Pointer<MpTextEmbedderOptions> options,
  Pointer<Pointer<Void>> task,
  Pointer<Pointer<Char>> error,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Char>,
    Pointer<MpTextFormatContext>,
    Pointer<MpEmbeddingResult>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpTextEmbedderEmbed', assetId: _asset)
external int embed(
  Pointer<Void> task,
  Pointer<Char> text,
  Pointer<MpTextFormatContext> context,
  Pointer<MpEmbeddingResult> result,
  Pointer<Pointer<Char>> error,
);

@Native<Int32 Function(Pointer<Void>, Pointer<Pointer<Char>>)>(
  symbol: 'MpTextEmbedderClose',
  assetId: _asset,
)
external int close(Pointer<Void> task, Pointer<Pointer<Char>> error);

@Native<Void Function(Pointer<MpEmbeddingResult>)>(
  symbol: 'MpTextEmbedderCloseResult',
  assetId: _asset,
)
external void closeResult(Pointer<MpEmbeddingResult> result);

@Native<Void Function(Pointer<Char>)>(symbol: 'MpErrorFree', assetId: _asset)
external void errorFree(Pointer<Char> error);
