/// Google's native Audio Classifier: a clips task is created on the calling
/// isolate and each clip is classified on a background isolate; a stream
/// task lives on a worker isolate of its own (native_audio_stream.dart).
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

export 'native_audio_stream.dart' show openNativeAudioStream;

/// Google's AUDIO_CLIPS and AUDIO_STREAM modes in its C API.
const audioClipsMode = 1, audioStreamMode = 2;

/// What Google's task is created from, in a form a worker isolate receives.
typedef NativeAudioSettings = ({
  Uint8List? modelBytes,
  String? modelPath,
  String? displayNamesLocale,
  int maxResults,
  double scoreThreshold,
  List<String> categoryAllowlist,
  List<String> categoryDenylist,
});

/// [options]' model and settings for [openNativeTask].
NativeAudioSettings nativeAudioSettings(AudioClassifierOptions options) => (
  modelBytes: options.modelBytes,
  modelPath: options.modelPath,
  displayNamesLocale: options.displayNamesLocale,
  maxResults: options.maxResults,
  scoreThreshold: options.scoreThreshold,
  categoryAllowlist: options.categoryAllowlist,
  categoryDenylist: options.categoryDenylist,
);

/// Copies the model's bytes, if [settings] has them, into native memory,
/// which the caller keeps until it closes Google's task: Google reads the
/// model there without copying it.
Pointer<Uint8>? nativeModel(NativeAudioSettings settings) {
  final bytes = settings.modelBytes;
  if (bytes == null) return null;
  final model = malloc<Uint8>(bytes.length);
  model.asTypedList(bytes.length).setAll(0, bytes);
  return model;
}

/// Creates Google's task in [runningMode] from [settings], reading the model
/// from [model] when it is in memory, and returns its handle. A stream
/// passes the [resultCallback] Google calls with each result.
Pointer<Void> openNativeTask(
  NativeAudioSettings settings,
  Pointer<Uint8>? model, {
  required int runningMode,
  Pointer<Void>? resultCallback,
}) => using((arena) {
  final native = arena<mp.MpAudioClassifierOptions>();
  native.ref.baseOptions
    ..fileDescriptor = -1
    ..delegate = 0
    ..hostSystem = mpHostSystem;
  if (model != null) {
    native.ref.baseOptions
      ..modelAssetBuffer = model.cast()
      ..modelAssetBufferCount = settings.modelBytes!.length;
  } else {
    native.ref.baseOptions.modelAssetPath = settings.modelPath!
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
        settings.displayNamesLocale?.toNativeUtf8(allocator: arena).cast() ??
        nullptr
    ..maxResults = settings.maxResults
    ..scoreThreshold = settings.scoreThreshold
    ..categoryAllowlist = strings(settings.categoryAllowlist)
    ..categoryAllowlistCount = settings.categoryAllowlist.length
    ..categoryDenylist = strings(settings.categoryDenylist)
    ..categoryDenylistCount = settings.categoryDenylist.length;
  native.ref
    ..runningMode = runningMode
    ..resultCallback = resultCallback ?? nullptr;
  final output = arena<Pointer<Void>>();
  checkedNativeCall((error) => mp.create(native, output, error));
  return output.value;
});

/// Opens Google's native Audio Classifier.
Future<AudioClassifierRunner> openNativeAudioClassifier(
  AudioClassifierOptions options,
) async {
  requireNativeAudioRuntime();
  final settings = nativeAudioSettings(options);
  final model = nativeModel(settings);
  try {
    final task = openNativeTask(
      settings,
      model,
      runningMode: audioClipsMode,
    ).address;
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
    checkedNativeCall((error) => mp.close(Pointer.fromAddress(_task), error));
    if (_model case final model?) malloc.free(model);
  });
}

/// Resolves core's runtime before the first call, to explain a missing one.
void requireNativeAudioRuntime() {
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
  final audio = nativeAudioData(samples, sampleRate, channels, arena);
  final result = arena<mp.MpAudioClassifierResult>();
  checkedNativeCall(
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

/// [samples] as Google's C API takes them, in memory from [arena].
Pointer<mp.MpAudioData> nativeAudioData(
  Float32List samples,
  double sampleRate,
  int channels,
  Arena arena,
) {
  final data = arena<Float>(samples.length);
  data.asTypedList(samples.length).setAll(0, samples);
  final audio = arena<mp.MpAudioData>();
  audio.ref
    ..numChannels = channels
    ..sampleRate = sampleRate
    ..audioData = data
    ..audioDataSize = samples.length;
  return audio;
}

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
                  categoryName: nativeString(
                    result.classifications[h].categories[i].categoryName,
                  ),
                  displayName: nativeString(
                    result.classifications[h].categories[i].displayName,
                  ),
                ),
            ],
            headIndex: result.classifications[h].headIndex,
            headName: nativeString(result.classifications[h].headName),
          ),
      ],
    );

/// A nullable C string, decoded before Google or the bridge frees it.
String? nativeString(Pointer<Char> value) =>
    value == nullptr ? null : value.cast<Utf8>().toDartString();

/// Runs a call of Google's C API, turning a failed status into Google's
/// message as a [TaskException].
void checkedNativeCall(int Function(Pointer<Pointer<Char>> error) call) =>
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
