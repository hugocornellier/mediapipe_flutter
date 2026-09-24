import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../audio_task_backend.dart';
import 'audio_classifier_backend.dart';
import 'audio_types.dart';

import 'third_party/mediapipe/audio_classifier_bindings.dart' as mp;

/// Google's official Audio Classifier (for example YAMNet) on audio clips.
///
/// The native task is created once; each [classify] runs on a background
/// isolate. Where a platform plugin installs Google's mobile SDK
/// (audio_task_backend.dart), the task runs there instead. Await [dispose]
/// when finished.
final class AudioClassifier {
  AudioClassifier._(this._task, this._model) : _backend = null;

  AudioClassifier._onBackend(BackendAudioClassifier this._backend)
    : _task = 0,
      _model = null;

  final BackendAudioClassifier? _backend;

  final int _task;

  /// The model bytes, kept alive while the native task may read them.
  final Pointer<Uint8>? _model;
  Future<void>? _disposing;
  Future<void> _tail = Future.value();

  /// Creates the task on the calling isolate.
  static Future<AudioClassifier> create(AudioClassifierOptions options) async {
    if (audioTaskBackendFactory != null) {
      return AudioClassifier._onBackend(
        await BackendAudioClassifier.create(options),
      );
    }
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
    if (_backend case final backend?) return backend.classify(audio);
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
  Future<void> dispose() =>
      _backend?.dispose() ??
      (_disposing ??= _tail.then((_) {
        _checked((error) => mp.close(Pointer.fromAddress(_task), error));
        if (_model case final model?) malloc.free(model);
      }));
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
