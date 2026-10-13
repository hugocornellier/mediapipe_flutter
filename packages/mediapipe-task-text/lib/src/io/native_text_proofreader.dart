import 'dart:ffi';
import 'package:ffi/ffi.dart';

import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/task_worker.dart';
import 'package:mediapipe_core/native_structs.dart'
    show checkNativeStatus, fillBaseOptions, nativeString;

import '../types/options.dart';
import '../types/results.dart';
import 'native_text_stream.dart';
import 'third_party/mediapipe/proofreader_bindings.dart' as mp;

/// Native task owner, used serially by one persistent worker isolate.
final class NativeTextProofreader
    extends WorkerTask<String, TextProofreaderResult, TextProofreaderUpdate> {
  /// Load the official CPU task.
  NativeTextProofreader(TextProofreaderOptions options) {
    if (options.delegate != Delegate.cpu) {
      throw UnsupportedError('TextProofreader supports the CPU delegate only.');
    }
    using((arena) {
      final native = arena<mp.MpTextProofreaderOptions>();
      fillBaseOptions(
        native.ref.baseOptions,
        arena,
        modelPath: options.modelPath,
      );
      native.ref
        ..maxNumTokens = options.maxNumTokens ?? 0
        // Google's default: errors only.
        ..minLogSeverity = 4;
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
  @override
  TextProofreaderResult run(String input) => using((arena) {
    final output = arena<Pointer<mp.MpTextProofreaderResult>>();
    _checked(
      (error) => mp.proofread(
        _handle,
        input.toNativeUtf8(allocator: arena).cast(),
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
        proofreadText: nativeString(result.proofreadText),
        corrections: _corrections(result.corrections, result.correctionsCount),
      );
    } finally {
      mp.closeResult(output.value);
    }
  });

  /// Await the terminal native update before releasing the callback/context.
  @override
  Future<void> stream(
    String input,
    void Function(TextProofreaderUpdate) emit,
  ) => receiveNativeTextStream(
    submit: (context) => using((arena) {
      _checked(
        (error) => mp.proofreadStreaming(
          _handle,
          input.toNativeUtf8(allocator: arena).cast(),
          Native.addressOf<NativeFunction<mp.ProofreaderCallback>>(
            mp.streamCallback,
          ),
          context,
          error,
        ),
      );
    }),
    decode: (result, terminal) => TextProofreaderUpdate(
      chunk: nativeString(result.text),
      done: terminal,
      corrections: _corrections(result.corrections, result.correctionsCount),
    ),
    emit: emit,
    exception: TaskException.new,
  );

  /// Close after all native requests have completed.
  @override
  void close() {
    if (_handle == nullptr) return;
    final handle = _handle;
    _handle = nullptr;
    _checked((error) => mp.close(handle, error));
  }
}

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
        text: nativeString(values[i].text) ?? '',
      ),
  ];
}

void _checked(int Function(Pointer<Pointer<Char>>) call) =>
    checkNativeStatus(call, mp.errorFree);
