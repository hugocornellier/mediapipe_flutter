// Copyright 2026 The MediaPipe Authors. Licensed under Apache-2.0.
// Adapted from mediapipe==1.0.1 text/text_proofreader.py ctypes definitions.
// The local bridge only owns callback copies; inference uses Google's exports.
// ignore_for_file: public_member_api_docs
import 'dart:ffi';
import 'embedding_gemma_bindings.dart' show MpBaseOptions;
import 'text_stream_bindings.dart';
export 'text_stream_bindings.dart';

const _runtime = 'package:mediapipe_flutter_core/tasks_1_0_1.dylib';
const _bridge = 'package:mediapipe_flutter_text/text_stream_bridge.dylib';

final class MpTextProofreaderOptions extends Struct {
  external MpBaseOptions baseOptions;
  @Int32()
  external int maxNumTokens;
  external Pointer<Char> cacheDir;
}

final class MpTextProofreaderResult extends Struct {
  external Pointer<Char> proofreadText;
  @Int32()
  external int correctionsCount;
  external Pointer<MpCorrection> corrections;
}

final class MpTextProofreaderStreamResult extends Struct {
  external Pointer<Char> chunk;
  @Int32()
  external int correctionsCount;
  external Pointer<MpCorrection> corrections;
  @Bool()
  external bool done;
}

typedef ProofreaderCallback =
    Void Function(
      Pointer<Void>,
      Pointer<MpTextProofreaderStreamResult>,
      Pointer<Char>,
    );

@Native<
  Int32 Function(
    Pointer<MpTextProofreaderOptions>,
    Pointer<Pointer<Void>>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpTextProofreaderCreate', assetId: _runtime)
external int create(
  Pointer<MpTextProofreaderOptions> options,
  Pointer<Pointer<Void>> handle,
  Pointer<Pointer<Char>> error,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Char>,
    Pointer<Pointer<MpTextProofreaderResult>>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpTextProofreaderProofread', assetId: _runtime)
external int proofread(
  Pointer<Void> handle,
  Pointer<Char> text,
  Pointer<Pointer<MpTextProofreaderResult>> result,
  Pointer<Pointer<Char>> error,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Char>,
    Pointer<NativeFunction<ProofreaderCallback>>,
    Pointer<Void>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpTextProofreaderProofreadStreaming', assetId: _runtime)
external int proofreadStreaming(
  Pointer<Void> handle,
  Pointer<Char> text,
  Pointer<NativeFunction<ProofreaderCallback>> callback,
  Pointer<Void> context,
  Pointer<Pointer<Char>> error,
);

@Native<Int32 Function(Pointer<Void>, Pointer<Pointer<Char>>)>(
  symbol: 'MpTextProofreaderClose',
  assetId: _runtime,
)
external int close(Pointer<Void> handle, Pointer<Pointer<Char>> error);

@Native<Void Function(Pointer<MpTextProofreaderResult>)>(
  symbol: 'MpTextProofreaderCloseResult',
  assetId: _runtime,
)
external void closeResult(Pointer<MpTextProofreaderResult> result);

@Native<Void Function(Pointer<Char>)>(symbol: 'MpErrorFree', assetId: _runtime)
external void errorFree(Pointer<Char> error);

@Native<ProofreaderCallback>(
  symbol: 'MpFlutterProofreaderCallback',
  assetId: _bridge,
)
external void streamCallback(
  Pointer<Void> context,
  Pointer<MpTextProofreaderStreamResult> result,
  Pointer<Char> error,
);
