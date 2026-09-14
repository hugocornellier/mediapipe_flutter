import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../interface/embedding_gemma_types.dart';
import 'third_party/mediapipe/embedding_gemma_bindings.dart' as mp;

/// Synchronous task owner, confined to the persistent worker isolate.
final class NativeEmbeddingGemma {
  /// Load Google's CPU task and acquire its native handle.
  NativeEmbeddingGemma(EmbeddingGemmaOptions options) {
    if (!Platform.isMacOS || options.delegate != TextDelegate.cpu) {
      throw UnsupportedError(
        'EmbeddingGemma currently supports CPU on macOS arm64 only.',
      );
    }
    using((arena) {
      final native = arena<mp.MpTextEmbedderOptions>();
      native.ref.baseOptions
        ..fileDescriptor = -1
        ..delegate = 0
        ..hostSystem = 2;
      if (options.modelPath case final path?) {
        native.ref.baseOptions.modelAssetPath = path
            .toNativeUtf8(allocator: arena)
            .cast();
      }
      if (options.modelBytes case final bytes?) {
        final buffer = arena<Uint8>(bytes.length);
        buffer.asTypedList(bytes.length).setAll(0, bytes);
        native.ref.baseOptions
          ..modelAssetBuffer = buffer.cast()
          ..modelAssetBufferCount = bytes.length;
      }
      native.ref.embedderOptions
        ..l2Normalize = options.l2Normalize
        ..quantize = options.quantize;
      final handle = arena<Pointer<Void>>();
      _checked((error) => mp.create(native, handle, error));
      _task = handle.value;
      if (_task == nullptr) throw StateError('MediaPipe returned no task.');
    });
  }

  Pointer<Void> _task = nullptr;
  EmbeddingGemmaException? _failure;

  /// Run official tokenization, formatting, inference and postprocessing.
  TextEmbeddingResult embed(String text, TextFormatContext? context) {
    if (_task == nullptr) throw StateError('EmbeddingGemma has been closed.');
    if (_failure case final error?) throw error;
    return using((arena) {
      final input = text.toNativeUtf8(allocator: arena).cast<Char>();
      var format = nullptr.cast<mp.MpTextFormatContext>();
      if (context != null) {
        format = arena<mp.MpTextFormatContext>();
        format.ref
          ..taskType = context.taskType.nativeValue
          ..role = context.role.nativeValue;
        if (context.title case final title?) {
          format.ref.title = title.toNativeUtf8(allocator: arena).cast();
        }
      }
      final output = arena<mp.MpEmbeddingResult>();
      var success = false;
      try {
        _checked((error) => mp.embed(_task, input, format, output, error));
        success = true;
        final result = output.ref;
        if (result.embeddingsCount == 0 || result.embeddings == nullptr) {
          throw StateError('MediaPipe returned no embeddings.');
        }
        return TextEmbeddingResult(
          timestampMs: result.hasTimestampMs ? result.timestampMs : null,
          embeddings: [
            for (var i = 0; i < result.embeddingsCount; i++)
              _copy(result.embeddings[i]),
          ],
        );
      } on EmbeddingGemmaException catch (error) {
        // Graph failures (including the official token limit) persist upstream.
        // Retain the error rather than submitting more work to a failed graph.
        _failure = error;
        rethrow;
      } finally {
        if (success) mp.closeResult(output);
      }
    });
  }

  /// Release the task once, including after a failed inference.
  void close() {
    if (_task == nullptr) return;
    final task = _task;
    _task = nullptr;
    _checked((error) => mp.close(task, error));
  }
}

TextEmbedding _copy(mp.MpEmbedding value) {
  if (value.valuesCount == 0 ||
      (value.floatEmbedding == nullptr) ==
          (value.quantizedEmbedding == nullptr)) {
    throw StateError('MediaPipe returned an invalid embedding.');
  }
  return TextEmbedding(
    floatValues: value.floatEmbedding == nullptr
        ? null
        : value.floatEmbedding.asTypedList(value.valuesCount),
    quantizedValues: value.quantizedEmbedding == nullptr
        ? null
        : value.quantizedEmbedding.asTypedList(value.valuesCount),
    headIndex: value.headIndex,
    headName: value.headName == nullptr
        ? null
        : value.headName.cast<Utf8>().toDartString(),
  );
}

void _checked(int Function(Pointer<Pointer<Char>>) action) => using((arena) {
  final error = arena<Pointer<Char>>();
  try {
    final status = action(error);
    if (status != 0) {
      throw EmbeddingGemmaException(
        error.value == nullptr
            ? 'MediaPipe operation failed.'
            : error.value.cast<Utf8>().toDartString(),
        status: status,
      );
    }
  } finally {
    if (error.value != nullptr) mp.errorFree(error.value);
  }
});
