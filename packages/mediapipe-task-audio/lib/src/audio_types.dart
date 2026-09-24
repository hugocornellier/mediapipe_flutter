import 'dart:typed_data';

import 'package:mediapipe_flutter_core/capabilities.dart';

import '../audio_task_backend.dart';

/// Why an Audio Classifier could not be created or run: Google's message.
final class AudioClassifierException implements Exception {
  /// Wraps Google's message for a failed call.
  const AudioClassifierException(this.message);

  /// Google's error text.
  final String message;

  @override
  String toString() => 'AudioClassifierException: $message';
}

/// The delegates the package can report; Google's audio task runs on CPU.
enum AudioDelegate {
  /// The CPU delegate, the only one the official 1.0.1 audio task serves.
  cpu,

  /// Reported unavailable; never accepted by [AudioClassifier.create].
  gpu,
}

/// Where Audio Classifier runs: CPU on the shared official 1.0.1 runtime,
/// which core provides for macOS arm64 (macOS 14+), and through Google's
/// browser runtime or mobile SDK where a platform plugin installs it.
Future<TaskCapabilities<AudioDelegate>>
queryAudioClassifierCapabilities() async =>
    audioClassifierCapabilitiesForPlatform(await currentTaskPlatform());

/// Evaluate support for an explicit platform snapshot without loading code.
TaskCapabilities<AudioDelegate> audioClassifierCapabilitiesForPlatform(
  TaskPlatform platform,
) => TaskCapabilities.cpuOnTargets(
  platform: platform,
  cpu: AudioDelegate.cpu,
  gpu: AudioDelegate.gpu,
  gpuUnavailableReason: "Google's official audio task runs on CPU only.",
  targets: {
    ...tasksRuntimeTargets,
    // A registered backend is Google's browser runtime or mobile SDK for
    // this very platform (mediapipe_flutter_audio_web, _android or _ios).
    if (audioTaskBackendFactory != null) ...{
      'web/unknown': null,
      'android/arm64': null,
      'android/x64': null,
      'ios/arm64': '15.0',
    },
  },
);

/// Samples to classify: interleaved frames at [sampleRate], in -1 to 1.
final class AudioData {
  /// Wraps [samples]; [channels] values make up one frame.
  AudioData({
    required this.samples,
    required this.sampleRate,
    this.channels = 1,
  }) {
    if (sampleRate <= 0) throw ArgumentError.value(sampleRate, 'sampleRate');
    if (channels < 1 || samples.length % channels != 0) {
      throw ArgumentError.value(channels, 'channels');
    }
  }

  /// Interleaved samples: frame 0's channels, then frame 1's, and so on.
  final Float32List samples;

  /// Frames per second.
  final double sampleRate;

  /// Values per frame.
  final int channels;
}

/// Options for [AudioClassifier.create], named as in Google's API.
final class AudioClassifierOptions {
  /// Exactly one of [modelPath] and [modelBytes].
  AudioClassifierOptions({
    this.modelPath,
    this.modelBytes,
    this.maxResults = -1,
    this.scoreThreshold = 0,
  }) {
    if ((modelPath == null) == (modelBytes == null)) {
      throw ArgumentError('Supply exactly one of modelPath and modelBytes.');
    }
    if (maxResults == 0) throw ArgumentError.value(maxResults, 'maxResults');
  }

  /// A model file on disk.
  final String? modelPath;

  /// A model already in memory.
  final Uint8List? modelBytes;

  /// The most categories per chunk; -1 for all.
  final int maxResults;

  /// Categories scoring below this are dropped.
  final double scoreThreshold;
}

/// One category and its score.
typedef AudioCategory = ({int index, double score, String? name});

/// The categories of one chunk of the clip, which starts at [timestampMs].
typedef AudioClassification = ({
  int timestampMs,
  List<AudioCategory> categories,
});
