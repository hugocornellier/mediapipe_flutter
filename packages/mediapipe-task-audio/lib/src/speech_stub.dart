/// Browsers have no native runtime, and Google's browser runtime has no
/// Audio Transcriber or Text to Speech.
library;

import 'package:mediapipe_core/mediapipe_core.dart';

import 'speech_runners.dart';
import 'speech_types.dart';

/// The native Audio Transcriber; browsers have none.
Future<AudioTranscriberRunner> openNativeAudioTranscriber(
  AudioTranscriberOptions options,
) async => throw _noBrowserTask('Audio Transcriber');

/// The native Text to Speech; browsers have none.
Future<TextToSpeechRunner> openNativeTextToSpeech(
  TextToSpeechOptions options,
) async => throw _noBrowserTask('Text to Speech');

RuntimeUnavailableException _noBrowserTask(String task) =>
    RuntimeUnavailableException(
      "Google's browser runtime has no $task.",
      fix: 'Run $task on Android, iOS, macOS, Linux or Windows.',
    );
