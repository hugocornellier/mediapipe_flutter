import 'dart:typed_data';

import 'package:mediapipe_core/io.dart';
import 'package:mediapipe_core/model_store.dart';
import 'package:mediapipe_text/interface.dart';

import '../../classic_text_runtime.dart';
import '../../../resolve_text_model.dart';

/// Owned options for the official MediaPipe 1.0.1 LanguageDetector.
// ignore: must_be_immutable
class LanguageDetectorOptions extends BaseLanguageDetectorOptions {
  /// Supply a filesystem model path or model bytes and official task options.
  LanguageDetectorOptions({
    this.model,
    BaseOptions? baseOptions,
    ClassifierOptions classifierOptions = const ClassifierOptions(),
  }) : _baseOptions = baseOptions == null
           ? null
           : copyTextBaseOptions(baseOptions),
       classifierOptions = copyTextClassifierOptions(classifierOptions) {
    if ((model == null) == (baseOptions == null)) {
      throw ArgumentError('Supply exactly one of model and baseOptions.');
    }
  }

  /// Pinned official model: the app's bundled copy, or a download when
  /// `ModelStore.allowDownloads` is true. Verified against its SHA-256.
  final DownloadAsset? model;
  BaseOptions? _baseOptions;

  /// Resolves a pinned model before creating a task.
  Future<void> prepareModel() => _resolveModel();

  Future<void> _resolveModel() async {
    if (model case final selected?) {
      _baseOptions = await resolveTextModel(selected);
    }
  }

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
  BaseOptions get baseOptions =>
      _baseOptions ??
      (throw StateError('Create the task before reading baseOptions.'));

  @override
  final ClassifierOptions classifierOptions;
}
