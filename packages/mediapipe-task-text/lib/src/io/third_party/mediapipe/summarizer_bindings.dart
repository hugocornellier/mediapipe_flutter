// Copyright 2026 The MediaPipe Authors. Licensed under Apache-2.0.
// Adapted from mediapipe==1.0.1 text/text_summarizer.py ctypes definitions.
// ignore_for_file: public_member_api_docs
import 'dart:ffi';
import 'embedding_gemma_bindings.dart' show MpBaseOptions;

const _runtime = 'package:mediapipe_flutter_core/tasks_1_0_1.dylib';
const _bridge = 'package:mediapipe_flutter_text/text_stream_bridge.dylib';

final class MpTextSummarizerOptions extends Struct {
  external MpBaseOptions baseOptions;
  @Int32()
  external int mode;
  @Int32()
  external int maxNumTokens;
  external Pointer<Char> cacheDir;
}

final class MpTextSummarizerResult extends Struct {
  external Pointer<Char> summary;
}

final class MpTextSummarizerStreamResult extends Struct {
  external Pointer<Char> chunk;
  @Bool()
  external bool done;
}

typedef SummarizerCallback =
    Void Function(
      Pointer<Void>,
      Pointer<MpTextSummarizerStreamResult>,
      Pointer<Char>,
    );

@Native<
  Int32 Function(
    Pointer<MpTextSummarizerOptions>,
    Pointer<Pointer<Void>>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpTextSummarizerCreate', assetId: _runtime)
external int create(
  Pointer<MpTextSummarizerOptions> options,
  Pointer<Pointer<Void>> handle,
  Pointer<Pointer<Char>> error,
);

// Unlike Proofreader, the caller allocates this result struct (one pointer).
@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Char>,
    Pointer<MpTextSummarizerResult>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpTextSummarizerSummarize', assetId: _runtime)
external int summarize(
  Pointer<Void> handle,
  Pointer<Char> text,
  Pointer<MpTextSummarizerResult> result,
  Pointer<Pointer<Char>> error,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Char>,
    Pointer<NativeFunction<SummarizerCallback>>,
    Pointer<Void>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpTextSummarizerSummarizeStreaming', assetId: _runtime)
external int summarizeStreaming(
  Pointer<Void> handle,
  Pointer<Char> text,
  Pointer<NativeFunction<SummarizerCallback>> callback,
  Pointer<Void> context,
  Pointer<Pointer<Char>> error,
);

@Native<Int32 Function(Pointer<Void>, Pointer<Pointer<Char>>)>(
  symbol: 'MpTextSummarizerClose',
  assetId: _runtime,
)
external int close(Pointer<Void> handle, Pointer<Pointer<Char>> error);

@Native<Void Function(Pointer<MpTextSummarizerResult>)>(
  symbol: 'MpTextSummarizerCloseResult',
  assetId: _runtime,
)
external void closeResult(Pointer<MpTextSummarizerResult> result);

@Native<Void Function(Pointer<Char>)>(symbol: 'MpErrorFree', assetId: _runtime)
external void errorFree(Pointer<Char> error);

@Native<SummarizerCallback>(
  symbol: 'MpFlutterSummarizerCallback',
  assetId: _bridge,
)
external void streamCallback(
  Pointer<Void> context,
  Pointer<MpTextSummarizerStreamResult> result,
  Pointer<Char> error,
);
