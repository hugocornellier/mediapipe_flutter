import 'dart:typed_data';
import 'package:mediapipe_flutter_core/io.dart';
import 'package:mediapipe_flutter_text/interface.dart';
import '../../classic_text_runtime.dart';

/// Owned options for the official MediaPipe 1.0.1 TextClassifier.
class TextClassifierOptions extends BaseTextClassifierOptions {
  /// Supply a filesystem model path or model bytes and official task options.
  TextClassifierOptions({
    required BaseOptions baseOptions,
    ClassifierOptions classifierOptions = const ClassifierOptions(),
  }) : baseOptions = copyTextBaseOptions(baseOptions),
       classifierOptions = copyTextClassifierOptions(classifierOptions);

  /// Load a filesystem path (not a Flutter asset key).
  factory TextClassifierOptions.fromAssetPath(
    String assetPath, {
    ClassifierOptions classifierOptions = const ClassifierOptions(),
  }) => TextClassifierOptions(
    baseOptions: BaseOptions.path(assetPath),
    classifierOptions: classifierOptions,
  );

  /// Snapshot bytes loaded from a Flutter asset or another source.
  factory TextClassifierOptions.fromAssetBuffer(
    Uint8List assetBuffer, {
    ClassifierOptions classifierOptions = const ClassifierOptions(),
  }) => TextClassifierOptions(
    baseOptions: BaseOptions.memory(assetBuffer),
    classifierOptions: classifierOptions,
  );

  @override
  final BaseOptions baseOptions;

  @override
  final ClassifierOptions classifierOptions;
}
