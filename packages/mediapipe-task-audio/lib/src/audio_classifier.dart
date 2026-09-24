import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mediapipe_flutter_core/capabilities.dart';

import 'third_party/mediapipe/audio_classifier_bindings.dart' as mp;

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
/// which core provides for macOS arm64 (macOS 14+).
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

/// Google's official Audio Classifier (for example YAMNet) on audio clips.
///
/// The native task is created once; each [classify] runs on a background
/// isolate. Await [dispose] when finished.
final class AudioClassifier {
  AudioClassifier._(this._task, this._model);

  final int _task;

  /// The model bytes, kept alive while the native task may read them.
  final Pointer<Uint8>? _model;
  Future<void>? _disposing;
  Future<void> _tail = Future.value();

  /// Creates the task on the calling isolate.
  static Future<AudioClassifier> create(AudioClassifierOptions options) async {
    final support = await queryAudioClassifierCapabilities();
    if (support.unavailableReasons[AudioDelegate.cpu] case final reason?) {
      throw AudioClassifierException(reason);
    }
    Pointer<Uint8>? model;
    if (options.modelBytes case final bytes?) {
      model = malloc<Uint8>(bytes.length);
      model.asTypedList(bytes.length).setAll(0, bytes);
    }
    try {
      final task = using((arena) {
        final native = arena<mp.MpAudioClassifierOptions>();
        native.ref.baseOptions
          ..fileDescriptor = -1
          ..delegate = 0
          ..hostSystem = 2;
        if (options.modelPath case final path?) {
          native.ref.baseOptions.modelAssetPath = path
              .toNativeUtf8(allocator: arena)
              .cast();
        }
        if (model != null) {
          native.ref.baseOptions
            ..modelAssetBuffer = model.cast()
            ..modelAssetBufferCount = options.modelBytes!.length;
        }
        native.ref.classifierOptions
          ..maxResults = options.maxResults
          ..scoreThreshold = options.scoreThreshold;
        native.ref.runningMode = 1;
        final output = arena<Pointer<Void>>();
        _checked((error) => mp.create(native, output, error));
        return output.value.address;
      });
      return AudioClassifier._(task, model);
    } catch (_) {
      if (model != null) malloc.free(model);
      rethrow;
    }
  }

  /// Classifies [audio], one result per chunk the model reads (0.975 s for
  /// YAMNet), in order.
  Future<List<AudioClassification>> classify(AudioData audio) {
    if (_disposing != null) {
      return Future.error(StateError('AudioClassifier has been disposed.'));
    }
    final task = _task;
    final samples = audio.samples;
    final rate = audio.sampleRate;
    final channels = audio.channels;
    final result = _tail.then(
      (_) => Isolate.run(() => _classify(task, samples, rate, channels)),
    );
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Waits for queued classifications, then closes the native task.
  Future<void> dispose() => _disposing ??= _tail.then((_) {
    _checked((error) => mp.close(Pointer.fromAddress(_task), error));
    if (_model case final model?) malloc.free(model);
  });
}

List<AudioClassification> _classify(
  int task,
  Float32List samples,
  double sampleRate,
  int channels,
) => using((arena) {
  final data = arena<Float>(samples.length);
  data.asTypedList(samples.length).setAll(0, samples);
  final audio = arena<mp.MpAudioData>();
  audio.ref
    ..numChannels = channels
    ..sampleRate = sampleRate
    ..audioData = data
    ..audioDataSize = samples.length;
  final result = arena<mp.MpAudioClassifierResult>();
  _checked(
    (error) => mp.classify(Pointer.fromAddress(task), audio, result, error),
  );
  try {
    return [
      for (var i = 0; i < result.ref.resultsCount; i++)
        _chunk(result.ref.results[i]),
    ];
  } finally {
    mp.closeResult(result);
  }
});

AudioClassification _chunk(mp.MpClassificationResult result) {
  final categories = <AudioCategory>[];
  if (result.classificationsCount > 0) {
    final head = result.classifications[0];
    for (var i = 0; i < head.categoriesCount; i++) {
      final category = head.categories[i];
      categories.add((
        index: category.index,
        score: category.score,
        name: category.categoryName == nullptr
            ? null
            : category.categoryName.cast<Utf8>().toDartString(),
      ));
    }
  }
  return (
    timestampMs: result.hasTimestampMs ? result.timestampMs : 0,
    categories: categories,
  );
}

void _checked(int Function(Pointer<Pointer<Char>> error) call) =>
    using((arena) {
      final error = arena<Pointer<Char>>();
      final status = call(error);
      if (status == 0) return;
      final message = error.value == nullptr
          ? 'MediaPipe status $status'
          : error.value.cast<Utf8>().toDartString();
      if (error.value != nullptr) mp.errorFree(error.value);
      throw AudioClassifierException(message);
    });
