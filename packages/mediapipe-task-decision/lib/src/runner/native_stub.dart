/// Browsers have no native runtime: Decision Maker runs through the
/// registered browser plugin, so reaching this means it did not register.
library;

import 'package:mediapipe_core/mediapipe_core.dart';

import '../decision_backend.dart';
import '../types/options.dart';

/// The native Decision Maker; browsers have none.
Future<DecisionBackend> openNativeDecisionMaker(
  DecisionMakerOptions options,
) async => throw const RuntimeUnavailableException(
  'The MediaPipe Decision browser plugin did not register.',
  fix:
      'Depend on mediapipe_decision as a Flutter plugin so its web '
      'registration runs before the first task is created.',
);
