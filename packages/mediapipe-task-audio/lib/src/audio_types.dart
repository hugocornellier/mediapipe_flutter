import 'dart:typed_data';

import 'package:mediapipe_core/capabilities.dart';
import 'package:mediapipe_core/mediapipe_exception.dart';
import 'package:mediapipe_core/model_store.dart';
import 'package:mediapipe_core/platform_interface.dart';

import 'audio_task_backend.dart';

/// Failure in a MediaPipe audio task, reported by Google's runtime.
final class AudioTaskException extends MediaPipeException {
  /// Wraps Google's message for a failed call, with the original [cause].
  const AudioTaskException(super.message, {super.cause});

  @override
  String toString() => 'AudioTaskException: $message';
}

/// The delegates the package can report; Google's audio task runs on CPU.
enum AudioDelegate {
  /// The CPU delegate, the only one the official 1.0.1 audio task serves.
  cpu,

  /// Reported unavailable; never accepted by [AudioClassifier.create].
  gpu,
}

/// Where Audio Classifier runs: CPU on core's shared runtime, Google's library
/// for macOS arm64 (macOS 14+), Linux x64 and Windows x64 and its iOS SDK
/// (iOS 15+, through the adapter core builds), and through Google's
/// browser runtime or Android SDK where a platform plugin installs it.
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
  runtimeVersion: tasksRuntimeVersionOn(platform),
  targets: {
    // Core's runtime, iOS included (its SDK adapter).
    ...tasksRuntimeTargets,
    // A registered backend is Google's browser runtime or Android SDK for
    // this very platform (mediapipe_audio or _android).
    if (audioTaskBackendFactory != null) ...{
      'web/unknown': null,
      'android/arm64': null,
      'android/x64': null,
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
  /// Supply exactly one pinned [model], [modelPath], or [modelBytes].
  AudioClassifierOptions({
    this.model,
    this.modelPath,
    Uint8List? modelBytes,
    this.maxResults = -1,
    this.scoreThreshold = 0,
  }) : modelBytes = modelBytes == null
           ? null
           : Uint8List.fromList(modelBytes).asUnmodifiableView() {
    if ([
          model,
          modelPath,
          modelBytes,
        ].where((source) => source != null).length !=
        1) {
      throw ArgumentError(
        'Supply exactly one of model, modelPath and modelBytes.',
      );
    }
    if (modelPath != null &&
        (modelPath!.isEmpty || modelPath!.contains('\u0000'))) {
      throw ArgumentError.value(modelPath, 'modelPath', 'Invalid model path.');
    }
    if (modelBytes != null && modelBytes.isEmpty) {
      throw ArgumentError.value(modelBytes, 'modelBytes', 'Must not be empty.');
    }
    if (maxResults == 0) throw ArgumentError.value(maxResults, 'maxResults');
  }

  /// Pinned official model, downloaded and verified when the task is created.
  final DownloadAsset? model;

  /// Resolve [model] while preserving the other classifier options.
  Future<AudioClassifierOptions> resolveModel() async {
    if (model case final selected?) {
      final source = await resolvePinnedModel(selected);
      return AudioClassifierOptions(
        modelPath: source.path,
        modelBytes: source.bytes,
        maxResults: maxResults,
        scoreThreshold: scoreThreshold,
      );
    }
    return this;
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
typedef AudioClassifierCategory = ({int index, double score, String? name});

/// The categories of one chunk of the clip, which starts at [timestampMs].
typedef AudioClassifierResult = ({
  int timestampMs,
  List<AudioClassifierCategory> categories,
});
