/// Google's native Audio Classifier: the task is created on the calling
/// isolate and each clip is classified on a background isolate.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/platform_interface.dart';

import '../runner.dart';
import '../third_party/mediapipe/audio_classifier_bindings.dart' as mp;
import '../types.dart';

/// Opens Google's native Audio Classifier.
Future<AudioClassifierRunner> openNativeAudioClassifier(
  AudioClassifierOptions options,
) async {
  _requireRuntime();
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
        ..hostSystem = mpHostSystem;
      if (model != null) {
        native.ref.baseOptions
          ..modelAssetBuffer = model.cast()
          ..modelAssetBufferCount = options.modelBytes!.length;
      } else {
        native.ref.baseOptions.modelAssetPath = options.modelPath!
            .toNativeUtf8(allocator: arena)
            .cast();
      }
      Pointer<Pointer<Char>> strings(List<String> values) {
        if (values.isEmpty) return nullptr;
        final array = arena<Pointer<Char>>(values.length);
        for (var i = 0; i < values.length; i++) {
          array[i] = values[i].toNativeUtf8(allocator: arena).cast();
        }
        return array;
      }

      native.ref.classifierOptions
        ..displayNamesLocale =
            options.displayNamesLocale?.toNativeUtf8(allocator: arena).cast() ??
            nullptr
        ..maxResults = options.maxResults
        ..scoreThreshold = options.scoreThreshold
        ..categoryAllowlist = strings(options.categoryAllowlist)
        ..categoryAllowlistCount = options.categoryAllowlist.length
        ..categoryDenylist = strings(options.categoryDenylist)
        ..categoryDenylistCount = options.categoryDenylist.length;
      // Google's AUDIO_CLIPS mode.
      native.ref.runningMode = 1;
      final output = arena<Pointer<Void>>();
      _checked((error) => mp.create(native, output, error));
      return output.value.address;
    });
    return _NativeAudioClassifier(task, model);
  } catch (_) {
    if (model != null) malloc.free(model);
    rethrow;
  }
}

final class _NativeAudioClassifier implements AudioClassifierRunner {
  _NativeAudioClassifier(this._task, this._model);

  final int _task;

  /// The model bytes, kept alive while the native task may read them.
  final Pointer<Uint8>? _model;
  Future<void>? _disposing;
  Future<void> _tail = Future.value();

  @override
  Future<List<AudioClassifierResult>> classify(AudioData audio) {
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

  @override
  Future<void> dispose() => _disposing ??= _tail.then((_) {
    _checked((error) => mp.close(Pointer.fromAddress(_task), error));
    if (_model case final model?) malloc.free(model);
  });
}

/// Resolves core's runtime before the first call, to explain a missing one.
void _requireRuntime() {
  try {
    Native.addressOf<
      NativeFunction<
        Int32 Function(
          Pointer<mp.MpAudioClassifierOptions>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Char>>,
        )
      >
    >(mp.create);
  } on ArgumentError catch (error) {
    if (missingLinuxGraphicsLibraries('$error') case final missing?) {
      throw missing;
    }
    throw RuntimeUnavailableException(
      'Audio Classifier runtime unavailable.',
      fix: tasksRuntimeUnavailable(
        'the Audio Classifier',
        Platform.operatingSystem,
      ),
    );
  }
}

List<AudioClassifierResult> _classify(
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

AudioClassifierResult _chunk(mp.MpClassificationResult result) =>
    AudioClassifierResult(
      timestampMilliseconds: result.hasTimestampMs ? result.timestampMs : 0,
      classifications: [
        for (var h = 0; h < result.classificationsCount; h++)
          Classifications(
            categories: [
              for (
                var i = 0;
                i < result.classifications[h].categoriesCount;
                i++
              )
                MediaPipeCategory(
                  index: result.classifications[h].categories[i].index,
                  score: result.classifications[h].categories[i].score,
                  categoryName: _string(
                    result.classifications[h].categories[i].categoryName,
                  ),
                  displayName: _string(
                    result.classifications[h].categories[i].displayName,
                  ),
                ),
            ],
            headIndex: result.classifications[h].headIndex,
            headName: _string(result.classifications[h].headName),
          ),
      ],
    );

String? _string(Pointer<Char> value) =>
    value == nullptr ? null : value.cast<Utf8>().toDartString();

void _checked(int Function(Pointer<Pointer<Char>> error) call) =>
    using((arena) {
      final error = arena<Pointer<Char>>();
      final status = call(error);
      if (status == 0) return;
      final message = error.value == nullptr
          ? 'MediaPipe status $status'
          : error.value.cast<Utf8>().toDartString();
      if (error.value != nullptr) mp.errorFree(error.value);
      throw TaskException(message, statusCode: status);
    });
