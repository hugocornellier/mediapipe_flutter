import 'dart:ffi';
import 'package:ffi/ffi.dart';
import '../../classic_text_runtime.dart';
import '../../third_party/mediapipe/classic_text_bindings.dart' as mp;
import 'language_detector_options.dart';
import 'language_detector_result.dart';

/// Synchronous MediaPipe 1.0.1 owner. Prefer LanguageDetector for Flutter UI work.
class LanguageDetectorExecutor
    extends NativeClassicTextTask<LanguageDetectorResult> {
  /// Load the official task and acquire its handle.
  LanguageDetectorExecutor(LanguageDetectorOptions options) {
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
      checkTextStatus((error) => mp.languageCreate(native, output, error));
      handle = output.value;
      if (handle == nullptr) {
        throw StateError('MediaPipe returned no LanguageDetector.');
      }
    });
  }

  /// Run official preprocessing, inference and postprocessing.
  LanguageDetectorResult detect(String text) {
    checkInput(text);
    return using((arena) {
      final output = arena<mp.MpLanguageDetectorResult>();
      checkTextStatus(
        (error) => mp.languageRun(
          handle,
          text.toNativeUtf8(allocator: arena).cast(),
          output,
          error,
        ),
      );
      try {
        return LanguageDetectorResult.native(output);
      } finally {
        // Google frees nested fields; the arena owns the outer result struct.
        mp.languageCloseResult(output);
      }
    });
  }

  @override
  LanguageDetectorResult run(String text) => detect(text);

  @override
  void close() {
    if (handle == nullptr) return;
    final task = handle;
    handle = nullptr;
    checkTextStatus((error) => mp.languageClose(task, error));
  }
}
