import 'dart:ffi';
import 'package:mediapipe_flutter_text/interface.dart';
import '../../classic_text_runtime.dart';
import '../../third_party/mediapipe/classic_text_bindings.dart' as mp;

/// Owned predictions. Optional dispose is idempotent and does not erase values.
class LanguageDetectorResult extends BaseLanguageDetectorResult {
  /// Snapshot Google's ordered language predictions.
  LanguageDetectorResult({required Iterable<LanguagePrediction> predictions})
    : predictions = List.unmodifiable(predictions);

  /// Copy a borrowed 1.0.1 result; the caller retains native ownership.
  factory LanguageDetectorResult.native(
    Pointer<mp.MpLanguageDetectorResult> pointer,
  ) => LanguageDetectorResult(
    predictions: [
      for (var i = 0; i < pointer.ref.predictionsCount; i++)
        LanguagePrediction(
          languageCode: textTaskString(
            pointer.ref.predictions[i].languageCode,
          )!,
          probability: pointer.ref.predictions[i].probability,
        ),
    ],
  );

  @override
  final List<LanguagePrediction> predictions;
}

/// An owned language code and probability.
class LanguagePrediction extends BaseLanguagePrediction {
  /// Keep the official output unchanged.
  LanguagePrediction({required this.languageCode, required this.probability});

  @override
  final String languageCode;

  @override
  final double probability;
}
