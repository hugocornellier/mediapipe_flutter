/// Browsers have no native runtime: Audio Classifier runs through the
/// registered browser plugin, so reaching this means it did not register.
library;

import 'package:mediapipe_core/mediapipe_core.dart';

import 'runner.dart';
import 'stream/results.dart';
import 'types.dart';

const _missing = RuntimeUnavailableException(
  'The MediaPipe audio browser plugin did not register.',
  fix:
      'Depend on mediapipe_audio as a Flutter plugin so its web '
      'registration runs before the first task is created.',
);

/// The native Audio Classifier; browsers have none.
Future<AudioClassifierRunner> openNativeAudioClassifier(
  AudioClassifierOptions options,
) async => throw _missing;

/// The native audio stream; browsers have none.
Future<AudioStreamRunner> openNativeAudioStream(
  AudioClassifierOptions options,
  AudioStreamResults results,
) async => throw _missing;
