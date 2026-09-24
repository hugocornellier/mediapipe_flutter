import 'dart:typed_data';

import 'package:mediapipe_flutter_core/io.dart';
import 'package:mediapipe_flutter_text/interface.dart';

import '../../classic_text_runtime.dart';

/// Owned options for the official MediaPipe 1.0.1 LanguageDetector.
class LanguageDetectorOptions extends BaseLanguageDetectorOptions {
  /// Supply a filesystem model path or model bytes and official task options.
  LanguageDetectorOptions({
    required BaseOptions baseOptions,
    ClassifierOptions classifierOptions = const ClassifierOptions(),
  }) : baseOptions = copyTextBaseOptions(baseOptions),
       classifierOptions = copyTextClassifierOptions(classifierOptions);

  /// Load a filesystem path (not a Flutter asset key).
  factory LanguageDetectorOptions.fromAssetPath(
    String assetPath, {
    ClassifierOptions classifierOptions = const ClassifierOptions(),
  }) => LanguageDetectorOptions(
    baseOptions: BaseOptions.path(assetPath),
    classifierOptions: classifierOptions,
  );

  /// Snapshot bytes loaded from a Flutter asset or another source.
  factory LanguageDetectorOptions.fromAssetBuffer(
    Uint8List assetBuffer, {
    ClassifierOptions classifierOptions = const ClassifierOptions(),
  }) => LanguageDetectorOptions(
    baseOptions: BaseOptions.memory(assetBuffer),
    classifierOptions: classifierOptions,
  );

  @override
  final BaseOptions baseOptions;

  @override
  final ClassifierOptions classifierOptions;
}
