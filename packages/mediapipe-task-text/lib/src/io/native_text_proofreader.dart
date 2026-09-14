import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../interface/text_proofreader_types.dart';
import 'third_party/mediapipe/proofreader_bindings.dart' as mp;

/// Native task owner, used serially by one persistent worker isolate.
final class NativeTextProofreader {
  /// Load the official CPU task.
  NativeTextProofreader(TextProofreaderOptions options) {
    if (!Platform.isMacOS || options.delegate != TextDelegate.cpu) {
      throw UnsupportedError(
        'TextProofreader currently supports macOS arm64 CPU only.',
      );
    }
    using((arena) {
      final native = arena<mp.MpTextProofreaderOptions>();
      native.ref.baseOptions
        ..fileDescriptor = -1
        ..delegate = 0
        ..hostSystem = 2
        ..modelAssetPath = options.modelPath
            .toNativeUtf8(allocator: arena)
            .cast();
      native.ref.maxNumTokens = options.maxNumTokens ?? 0;
      if (options.cacheDirectory case final directory?) {
        native.ref.cacheDir = directory.toNativeUtf8(allocator: arena).cast();
      }
      final handle = arena<Pointer<Void>>();
      _checked((error) => mp.create(native, handle, error));
      _handle = handle.value;
      if (_handle == nullptr) {
        throw StateError('MediaPipe returned no Proofreader.');
      }
    });
  }

  Pointer<Void> _handle = nullptr;

  /// Copy a completed result and close its native allocation before returning.
  TextProofreaderResult proofread(String text) => using((arena) {
    final output = arena<Pointer<mp.MpTextProofreaderResult>>();
    _checked(
      (error) => mp.proofread(
        _handle,
        text.toNativeUtf8(allocator: arena).cast(),
        output,
        error,
      ),
    );
    if (output.value == nullptr) {
      throw StateError('MediaPipe returned no result.');
    }
    try {
      final result = output.value.ref;
      return TextProofreaderResult(
        proofreadText: _string(result.proofreadText),
        corrections: _corrections(result.corrections, result.correctionsCount),
      );
    } finally {
      mp.closeResult(output.value);
    }
  });

  /// Await the terminal native update before releasing the callback/context.
  Future<void> stream(
    String text,
    void Function(TextProofreaderUpdate) emit,
  ) async {
    final complete = Completer<void>();
    Object? failure;
    final callback = NativeCallable<mp.TextEventSink>.listener((
      Pointer<mp.MpFlutterTextEvent> event,
      bool terminal,
    ) {
      try {
        if (event == nullptr) {
          throw const TextProofreaderException(
            'Could not allocate a streaming result copy.',
          );
        }
        final result = event.ref;
        if (result.copyError != 0) {
          throw TextProofreaderException(
            'Streaming callback copy failed (${result.copyError}).',
          );
        }
        if (result.error != nullptr) {
          throw TextProofreaderException(_string(result.error)!);
        }
        if (failure == null) {
          emit(
            TextProofreaderUpdate(
              chunk: _string(result.text),
              done: terminal,
              corrections: _corrections(
                result.corrections,
                result.correctionsCount,
              ),
            ),
          );
        }
      } catch (error) {
        failure ??= error;
      } finally {
        mp.eventFree(event);
        if (terminal && !complete.isCompleted) {
          if (failure case final error?) {
            complete.completeError(error);
          } else {
            complete.complete();
          }
        }
      }
    });
    Pointer<Void> context = nullptr;
    try {
      context = mp.streamCreate(callback.nativeFunction);
      if (context == nullptr) {
        throw StateError('Could not allocate a streaming context.');
      }
      using((arena) {
        _checked(
          (error) => mp.proofreadStreaming(
            _handle,
            text.toNativeUtf8(allocator: arena).cast(),
            Native.addressOf<NativeFunction<mp.ProofreaderCallback>>(
              mp.streamCallback,
            ),
            context,
            error,
          ),
        );
      });
      await complete.future;
    } finally {
      callback.close();
      if (context != nullptr) mp.streamFree(context);
    }
  }

  /// Close after all native requests have completed.
  void close() {
    if (_handle == nullptr) return;
    final handle = _handle;
    _handle = nullptr;
    _checked((error) => mp.close(handle, error));
  }
}

String? _string(Pointer<Char> pointer) =>
    pointer == nullptr ? null : pointer.cast<Utf8>().toDartString();

List<ProofreadingCorrection> _corrections(
  Pointer<mp.MpCorrection> values,
  int count,
) {
  if (count < 0 || (count > 0 && values == nullptr)) {
    throw StateError('Invalid native correction array.');
  }
  return [
    for (var i = 0; i < count; i++)
      ProofreadingCorrection(
        type: ProofreadingCorrectionType.values[values[i].type],
        text: _string(values[i].text) ?? '',
      ),
  ];
}

void _checked(int Function(Pointer<Pointer<Char>>) call) => using((arena) {
  final error = arena<Pointer<Char>>();
  try {
    final status = call(error);
    if (status != 0) {
      throw TextProofreaderException(
        _string(error.value) ?? 'MediaPipe operation failed.',
        status: status,
      );
    }
  } finally {
    if (error.value != nullptr) mp.errorFree(error.value);
  }
});
