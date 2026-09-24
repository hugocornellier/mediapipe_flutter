import 'dart:typed_data';

import 'package:mediapipe_flutter_core/io.dart';
import 'package:mediapipe_flutter_text/interface.dart';

import '../../classic_text_runtime.dart';

/// Owned options for the official MediaPipe 1.0.1 TextEmbedder.
class TextEmbedderOptions extends BaseTextEmbedderOptions {
  /// Supply a filesystem model path or model bytes and official task options.
  TextEmbedderOptions({
    required BaseOptions baseOptions,
    this.embedderOptions = const EmbedderOptions(),
  }) : baseOptions = copyTextBaseOptions(baseOptions);

  /// Load a filesystem path (not a Flutter asset key).
  factory TextEmbedderOptions.fromAssetPath(
    String assetPath, {
    EmbedderOptions embedderOptions = const EmbedderOptions(),
  }) => TextEmbedderOptions(
    baseOptions: BaseOptions.path(assetPath),
    embedderOptions: embedderOptions,
  );

  /// Snapshot bytes loaded from a Flutter asset or another source.
  factory TextEmbedderOptions.fromAssetBuffer(
    Uint8List assetBuffer, {
    EmbedderOptions embedderOptions = const EmbedderOptions(),
  }) => TextEmbedderOptions(
    baseOptions: BaseOptions.memory(assetBuffer),
    embedderOptions: embedderOptions,
  );

  @override
  final BaseOptions baseOptions;

  @override
  final EmbedderOptions embedderOptions;
}
