import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../interface/text_summarizer_types.dart';
import 'native_text_stream.dart';
import 'text_task_worker.dart';
import 'third_party/mediapipe/summarizer_bindings.dart' as mp;

/// Native Summarizer owner, constructed and used on one worker isolate.
final class NativeTextSummarizer
    implements NativeTextTask<TextSummarizerResult, TextSummarizerUpdate> {
  /// Create the official CPU pipeline without altering prompts or model bytes.
  NativeTextSummarizer(TextSummarizerOptions options) {
    if (!Platform.isMacOS || options.delegate != TextDelegate.cpu) {
      throw UnsupportedError(
        'TextSummarizer currently supports macOS arm64 CPU only.',
      );
    }
    using((arena) {
      final native = arena<mp.MpTextSummarizerOptions>();
      native.ref.baseOptions
        ..fileDescriptor = -1
        ..delegate = 0
        ..hostSystem = 2
        ..modelAssetPath = options.modelPath
            .toNativeUtf8(allocator: arena)
            .cast();
      native.ref
        ..mode = options.mode.index
        ..maxNumTokens = options.maxNumTokens ?? 0;
      if (options.cacheDirectory case final directory?) {
        native.ref.cacheDir = directory.toNativeUtf8(allocator: arena).cast();
      }
      final handle = arena<Pointer<Void>>();
      _checked((error) => mp.create(native, handle, error));
      _handle = handle.value;
      if (_handle == nullptr) {
        throw StateError('MediaPipe returned no Summarizer.');
      }
    });
  }

  Pointer<Void> _handle = nullptr;

  @override
  TextSummarizerResult run(String text) => using((arena) {
    final result = arena<mp.MpTextSummarizerResult>();
    _checked(
      (error) => mp.summarize(
        _handle,
        text.toNativeUtf8(allocator: arena).cast(),
        result,
        error,
      ),
    );
    try {
      return TextSummarizerResult(
        summary: nativeTextString(result.ref.summary),
      );
    } finally {
      // Google frees the payload. The arena frees the caller-owned struct.
      mp.closeResult(result);
    }
  });

  @override
  Future<void> stream(String text, void Function(TextSummarizerUpdate) emit) =>
      receiveNativeTextStream(
        submit: (context) => using((arena) {
          _checked(
            (error) => mp.summarizeStreaming(
              _handle,
              text.toNativeUtf8(allocator: arena).cast(),
              Native.addressOf<NativeFunction<mp.SummarizerCallback>>(
                mp.streamCallback,
              ),
              context,
              error,
            ),
          );
        }),
        decode: (result, terminal) => TextSummarizerUpdate(
          chunk: nativeTextString(result.text),
          done: terminal,
        ),
        emit: emit,
        exception: TextSummarizerException.new,
      );

  @override
  void close() {
    if (_handle == nullptr) return;
    final handle = _handle;
    _handle = nullptr;
    _checked((error) => mp.close(handle, error));
  }
}

void _checked(int Function(Pointer<Pointer<Char>>) call) => using((arena) {
  final error = arena<Pointer<Char>>();
  try {
    final status = call(error);
    if (status != 0) {
      throw TextSummarizerException(
        nativeTextString(error.value) ?? 'MediaPipe operation failed.',
        status: status,
      );
    }
  } finally {
    if (error.value != nullptr) mp.errorFree(error.value);
  }
});
