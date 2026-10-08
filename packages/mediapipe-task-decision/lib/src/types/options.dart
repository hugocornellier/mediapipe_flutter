/// Decision Maker's options: core's model source and delegate plus Google's
/// token limit, validated the same way on every platform.
library;

import 'package:mediapipe_core/mediapipe_core.dart';

import '../../models.dart' show DecisionModels;

/// Options for Google's Decision Maker.
final class DecisionMakerOptions extends TaskOptions {
  /// [maxNumTokens] defaults to Google's 4096.
  DecisionMakerOptions({
    super.model,
    super.modelPath,
    super.modelBytes,
    super.delegate,
    this.maxNumTokens = 4096,
  }) : super(family: 'mediapipe_decision', registry: DecisionModels.byName) {
    if (maxNumTokens <= 0) {
      throw ArgumentError.value(maxNumTokens, 'maxNumTokens', 'Must be > 0.');
    }
  }

  /// The most tokens of input context Google's engine processes.
  final int maxNumTokens;
}
