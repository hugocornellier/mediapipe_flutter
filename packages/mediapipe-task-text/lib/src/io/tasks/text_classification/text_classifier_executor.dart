import 'dart:ffi';
import 'package:ffi/ffi.dart';
import '../../classic_text_runtime.dart';
import '../../third_party/mediapipe/classic_text_bindings.dart' as mp;
import 'text_classifier_options.dart';
import 'text_classifier_result.dart';

/// Synchronous MediaPipe 1.0.1 owner. Prefer TextClassifier for Flutter UI work.
class TextClassifierExecutor
    extends NativeClassicTextTask<TextClassifierResult> {
  /// Load the official task and acquire its handle.
  TextClassifierExecutor(TextClassifierOptions options) {
    requireTextTasksRuntime();
    using((arena) {
      final native = arena<mp.MpTextClassifierOptions>();
      fillTextBaseOptions(native.ref.baseOptions, options.baseOptions, arena);
      fillTextClassifierOptions(
        native.ref.classifierOptions,
        options.classifierOptions,
        arena,
      );
      final output = arena<Pointer<Void>>();
      checkTextStatus((error) => mp.classifierCreate(native, output, error));
      handle = output.value;
      if (handle == nullptr) {
        throw StateError('MediaPipe returned no TextClassifier.');
      }
    });
  }

  /// Run official preprocessing, inference and postprocessing.
  TextClassifierResult classify(String text) {
    checkInput(text);
    return using((arena) {
      final output = arena<mp.MpClassificationResult>();
      checkTextStatus(
        (error) => mp.classifierRun(
          handle,
          text.toNativeUtf8(allocator: arena).cast(),
          output,
          error,
        ),
      );
      try {
        return TextClassifierResult.native(output);
      } finally {
        // Google frees nested fields; the arena owns the outer result struct.
        mp.classifierCloseResult(output);
      }
    });
  }

  @override
  TextClassifierResult run(String text) => classify(text);

  @override
  void close() {
    if (handle == nullptr) return;
    final task = handle;
    handle = nullptr;
    checkTextStatus((error) => mp.classifierClose(task, error));
  }
}
