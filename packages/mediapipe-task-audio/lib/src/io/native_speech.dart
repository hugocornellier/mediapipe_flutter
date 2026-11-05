/// Google's native Audio Transcriber and Text to Speech, each made, used and
/// closed on a worker isolate of its own, so loading the model and every
/// request stay off the calling isolate.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/native_structs.dart'
    show checkNativeStatus, fillBaseOptions, nativeString;
import 'package:mediapipe_core/platform_interface.dart';
import 'package:mediapipe_core/task_worker.dart';

import '../speech_runners.dart';
import '../speech_types.dart';
import '../third_party/mediapipe/audio_transcriber_bindings.dart' as asr;
import '../third_party/mediapipe/text_to_speech_bindings.dart' as tts;
import 'native_audio_classifier.dart' show checkedNativeCall;

/// Opens Google's Audio Transcriber on a worker.
Future<AudioTranscriberRunner> openNativeAudioTranscriber(
  AudioTranscriberOptions options,
) async {
  _requireSpeechRuntime('the Audio Transcriber');
  final worker = _TranscriberWorker();
  await worker.start(_transcriberSettings(options), _NativeTranscriber.new);
  return worker;
}

/// Opens Google's Text to Speech on a worker.
Future<TextToSpeechRunner> openNativeTextToSpeech(
  TextToSpeechOptions options,
) async {
  _requireSpeechRuntime('Text to Speech');
  final worker = _TextToSpeechWorker();
  await worker.start(_textToSpeechSettings(options), _NativeTextToSpeech.new);
  return worker;
}

/// Resolves core's runtime before the worker starts, to explain a missing
/// one.
void _requireSpeechRuntime(String task) {
  try {
    Native.addressOf<
      NativeFunction<
        Int32 Function(
          Pointer<asr.MpAudioTranscriberOptions>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Char>>,
        )
      >
    >(asr.create);
  } on ArgumentError catch (error) {
    if (missingLinuxGraphicsLibraries('$error') case final missing?) {
      throw missing;
    }
    throw RuntimeUnavailableException(
      '${task[0].toUpperCase()}${task.substring(1)} runtime unavailable.',
      fix: tasksRuntimeUnavailable(task, Platform.operatingSystem),
    );
  }
}

/// Google's tasks read the model from a file: a pinned model resolves to
/// one on native platforms.
String _modelFile(TaskOptions options) =>
    options.modelPath ??
    (throw TaskException(
      "Google's speech tasks read their model from a file; this model "
      'resolved to bytes.',
    ));

// Settings cross to the worker as plain records.

typedef _TranscriberSettings = ({
  String modelPath,
  int sampleRateHz,
  bool enableInterimResults,
  int modelArchitecture,
  String? prompt,
  String? cacheDirectory,
});

_TranscriberSettings _transcriberSettings(AudioTranscriberOptions options) => (
  modelPath: _modelFile(options),
  sampleRateHz: options.sampleRateHz,
  enableInterimResults: options.enableInterimResults,
  modelArchitecture: options.modelArchitecture.index,
  prompt: options.prompt,
  cacheDirectory: options.cacheDirectory,
);

typedef _TextToSpeechSettings = ({
  String modelPath,
  String? defaultVoiceId,
  String? defaultLocale,
  double speakingRate,
  int targetBucket,
  String? cacheDirectory,
});

_TextToSpeechSettings _textToSpeechSettings(TextToSpeechOptions options) => (
  modelPath: _modelFile(options),
  defaultVoiceId: options.defaultVoiceId,
  defaultLocale: options.defaultLocale,
  speakingRate: options.speakingRate,
  targetBucket: options.targetBucket,
  cacheDirectory: options.cacheDirectory,
);

/// [value] in [arena], or null when it is null or empty, as Google's Python
/// passes optional strings.
Pointer<Char> _optional(String? value, Arena arena) =>
    value == null || value.isEmpty
    ? nullptr
    : value.toNativeUtf8(allocator: arena).cast();

// The Audio Transcriber.

/// A transcriber request: samples to transcribe, or a flush, or a warm-up.
sealed class _TranscriberRequest {
  const _TranscriberRequest();
}

final class _Transcribe extends _TranscriberRequest {
  const _Transcribe(this.samples, this.endOfStream);
  final Float32List samples;
  final bool endOfStream;
}

final class _FinishStream extends _TranscriberRequest {
  const _FinishStream();
}

final class _Prewarm extends _TranscriberRequest {
  const _Prewarm();
}

final class _TranscriberWorker
    extends TaskWorker<_TranscriberRequest, AudioTranscriberResult?, Never>
    implements AudioTranscriberRunner {
  _TranscriberWorker() : super('AudioTranscriber');

  @override
  Future<AudioTranscriberResult> transcribe(
    Float32List samples,
    bool endOfStream,
  ) async => (await run(_Transcribe(samples, endOfStream)))!;

  @override
  Future<AudioTranscriberResult> finishStream() async =>
      (await run(const _FinishStream()))!;

  @override
  Future<void> prewarm() => run(const _Prewarm());
}

final class _NativeTranscriber
    extends WorkerTask<_TranscriberRequest, AudioTranscriberResult?, Never> {
  _NativeTranscriber(_TranscriberSettings settings) {
    using((arena) {
      final native = arena<asr.MpAudioTranscriberOptions>();
      fillBaseOptions(
        native.ref.baseOptions,
        arena,
        modelPath: settings.modelPath,
      );
      native.ref
        ..sampleRateHz = settings.sampleRateHz
        ..enableInterimResults = settings.enableInterimResults
        ..modelArchitecture = settings.modelArchitecture
        ..prompt = _optional(settings.prompt, arena)
        ..cacheDir = _optional(settings.cacheDirectory, arena);
      final output = arena<Pointer<Void>>();
      checkedNativeCall((error) => asr.create(native, output, error));
      _handle = output.value;
    });
  }

  late Pointer<Void> _handle;

  @override
  AudioTranscriberResult? run(_TranscriberRequest input) => using(
    (arena) => switch (input) {
      _Transcribe(:final samples, :final endOfStream) => _result(arena, (
        result,
        error,
      ) {
        final data = arena<Float>(samples.isEmpty ? 1 : samples.length);
        data.asTypedList(samples.length).setAll(0, samples);
        return asr.transcribe(
          _handle,
          data,
          samples.length,
          endOfStream,
          result,
          error,
        );
      }),
      _FinishStream() => _result(
        arena,
        (result, error) => asr.finishStream(_handle, result, error),
      ),
      _Prewarm() => () {
        checkedNativeCall((error) => asr.prewarm(_handle, error));
        return null;
      }(),
    },
  );

  AudioTranscriberResult _result(
    Arena arena,
    int Function(
      Pointer<asr.MpAudioTranscriberResult> result,
      Pointer<Pointer<Char>> error,
    )
    call,
  ) {
    final result = arena<asr.MpAudioTranscriberResult>();
    checkedNativeCall((error) => call(result, error));
    try {
      return AudioTranscriberResult([
        for (var i = 0; i < result.ref.segmentsCount; i++)
          if (result.ref.segments[i] case final segment)
            TranscriptionSegment(
              transcript: nativeString(segment.transcript) ?? '',
              isFinal: segment.isFinal,
              fromTimestampMilliseconds: segment.fromTimestampMs,
              toTimestampMilliseconds: segment.toTimestampMs,
            ),
      ]);
    } finally {
      asr.closeResult(result);
    }
  }

  @override
  void close() => checkedNativeCall((error) => asr.close(_handle, error));
}

// Text to Speech.

/// A Text to Speech request: list the voices, or synthesize [text].
final class _TextToSpeechRequest {
  const _TextToSpeechRequest.voices()
    : text = null,
      voiceId = null,
      locale = null,
      cancelFlag = 0;

  const _TextToSpeechRequest.synthesize(
    String this.text,
    this.voiceId,
    this.locale, {
    this.cancelFlag = 0,
  });

  final String? text;
  final String? voiceId;
  final String? locale;

  /// A stream's cancel flag: the address of a byte the calling isolate sets
  /// to 1 to stop it.
  final int cancelFlag;
}

final class _TextToSpeechWorker
    extends TaskWorker<_TextToSpeechRequest, Object?, TextToSpeechResult>
    implements TextToSpeechRunner {
  _TextToSpeechWorker() : super('TextToSpeech');

  @override
  Future<List<TextToSpeechVoice>> listVoices() async =>
      (await run(const _TextToSpeechRequest.voices()))!
          as List<TextToSpeechVoice>;

  @override
  Future<TextToSpeechResult> synthesize(
    String text,
    String? voiceId,
    String? locale,
  ) async =>
      (await run(_TextToSpeechRequest.synthesize(text, voiceId, locale)))!
          as TextToSpeechResult;

  /// The worker reads Google's stream chunk by chunk and checks a flag in
  /// native memory before each read, which a cancel sets: the worker owns
  /// Google's stream handle, so no other thread touches it after it closes.
  @override
  Stream<TextToSpeechResult> synthesizeStream(
    String text,
    String? voiceId,
    String? locale,
  ) {
    final flag = calloc<Uint8>();
    final Stream<TextToSpeechResult> chunks;
    try {
      chunks = stream(
        _TextToSpeechRequest.synthesize(
          text,
          voiceId,
          locale,
          cancelFlag: flag.address,
        ),
      );
    } catch (_) {
      calloc.free(flag);
      rethrow;
    }
    StreamSubscription<TextToSpeechResult>? subscription;
    var freed = false;
    void free() {
      if (freed) return;
      freed = true;
      calloc.free(flag);
    }

    late final StreamController<TextToSpeechResult> controller;
    controller = StreamController(
      onListen: () {
        subscription = chunks.listen(
          controller.add,
          onError: controller.addError,
          onDone: () {
            free();
            unawaited(controller.close());
          },
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () async {
        // Closing the controller after onDone also lands here, with the
        // flag already freed.
        if (freed) return;
        flag.value = 1;
        // Waits for the worker to finish the request.
        await subscription?.cancel();
        free();
      },
    );
    return controller.stream;
  }
}

final class _NativeTextToSpeech
    extends WorkerTask<_TextToSpeechRequest, Object?, TextToSpeechResult> {
  _NativeTextToSpeech(_TextToSpeechSettings settings) {
    using((arena) {
      final native = arena<tts.MpTextToSpeechOptions>();
      fillBaseOptions(
        native.ref.baseOptions,
        arena,
        modelPath: settings.modelPath,
      );
      native.ref
        ..defaultVoiceId = _optional(settings.defaultVoiceId, arena)
        ..defaultLocale = _optional(settings.defaultLocale, arena)
        ..speakingRate = settings.speakingRate
        ..targetBucket = settings.targetBucket
        ..cacheDirectory = _optional(settings.cacheDirectory, arena);
      final output = arena<Pointer<Void>>();
      _checked((error) => tts.create(native, output, error));
      _handle = output.value;
    });
  }

  late Pointer<Void> _handle;

  @override
  Object? run(_TextToSpeechRequest input) => using((arena) {
    final text = input.text;
    if (text == null) return _voices(arena);
    final result = arena<tts.MpTextToSpeechAudioResult>();
    _checked(
      (error) => tts.synthesize(
        _handle,
        text.toNativeUtf8(allocator: arena).cast(),
        _synthesisOptions(input, arena),
        result,
        error,
      ),
    );
    return _audio(result, text);
  });

  @override
  Future<void> stream(
    _TextToSpeechRequest input,
    void Function(TextToSpeechResult update) emit,
  ) async {
    final text = input.text!;
    final cancelled = Pointer<Uint8>.fromAddress(input.cancelFlag);
    final stream = using((arena) {
      final output = arena<Pointer<Void>>();
      _checked(
        (error) => tts.startStream(
          _handle,
          text.toNativeUtf8(allocator: arena).cast(),
          _synthesisOptions(input, arena),
          true,
          output,
          error,
        ),
      );
      return output.value;
    });
    try {
      while (cancelled.value == 0) {
        final chunk = using((arena) {
          final result = arena<tts.MpTextToSpeechAudioResult>();
          final index = arena<Int32>();
          final last = arena<Bool>();
          final error = arena<Pointer<Char>>();
          final status = tts.streamReadNext(stream, result, index, last, error);
          if (status == tts.mpOutOfRange) {
            if (error.value != nullptr) tts.freeError(error.value);
            return null;
          }
          _checked((out) {
            out.value = error.value;
            return status;
          });
          return _audio(
            result,
            text,
            chunkIndex: index.value,
            isFinal: last.value,
          );
        });
        if (chunk == null) break;
        emit(chunk);
      }
    } finally {
      if (cancelled.value != 0) tts.streamCancel(stream);
      tts.streamClose(stream);
    }
  }

  Pointer<tts.MpTextToSpeechSynthesisOptions> _synthesisOptions(
    _TextToSpeechRequest input,
    Arena arena,
  ) {
    final options = arena<tts.MpTextToSpeechSynthesisOptions>();
    options.ref
      ..voiceId = _optional(input.voiceId, arena)
      ..locale = _optional(input.locale, arena);
    return options;
  }

  List<TextToSpeechVoice> _voices(Arena arena) {
    final list = arena<tts.MpTextToSpeechVoiceList>();
    _checked((error) => tts.listVoices(_handle, list, error));
    try {
      return [
        for (var i = 0; i < list.ref.numVoices; i++)
          if (list.ref.voices[i] case final voice)
            TextToSpeechVoice(
              voiceId: nativeString(voice.voiceId) ?? '',
              displayName: nativeString(voice.displayName) ?? '',
              locale: nativeString(voice.locale) ?? '',
              sampleRateHz: voice.sampleRateHz,
              isDownloaded: voice.isDownloaded,
            ),
      ];
    } finally {
      tts.voiceListFree(list);
    }
  }

  /// Copies Google's [result] for [text], then frees it.
  TextToSpeechResult _audio(
    Pointer<tts.MpTextToSpeechAudioResult> result,
    String text, {
    int chunkIndex = 0,
    bool isFinal = true,
  }) {
    try {
      final count = result.ref.numSamples;
      final samples = result.ref.samples == nullptr || count == 0
          ? Float32List(0)
          : Float32List.fromList(result.ref.samples.asTypedList(count));
      final words = result.ref.wordTimestamps;
      final indices = words == nullptr ? null : utf16Indices(text);
      return TextToSpeechResult(
        samples: samples,
        sampleRateHz: result.ref.sampleRateHz,
        chunkIndex: chunkIndex,
        isFinal: isFinal,
        wordTimestamps: [
          if (indices != null)
            for (var i = 0; i < result.ref.numWordTimestamps; i++)
              if (words[i] case final word)
                WordTimestamp(
                  word: nativeString(word.word) ?? '',
                  start: indices[word.startChar.clamp(0, indices.length - 1)],
                  end: indices[word.endChar.clamp(0, indices.length - 1)],
                  startSeconds: word.startSec,
                  endSeconds: word.endSec,
                ),
        ],
      );
    } finally {
      tts.freeAudioResult(result);
    }
  }

  @override
  void close() => tts.close(_handle);
}

/// For each UTF-8 byte offset of [text], as Google's word timestamps give
/// them, the UTF-16 index of the character it falls in; the last entry is
/// the text's length.
Int32List utf16Indices(String text) {
  final runes = text.runes;
  var length = 0;
  for (final rune in runes) {
    length += _utf8Length(rune);
  }
  final indices = Int32List(length + 1);
  var byte = 0, index = 0;
  for (final rune in runes) {
    final size = _utf8Length(rune);
    indices.fillRange(byte, byte + size, index);
    byte += size;
    index += rune > 0xffff ? 2 : 1;
  }
  indices[byte] = index;
  return indices;
}

/// A lone surrogate is encoded as U+FFFD, three bytes, as toNativeUtf8 does.
int _utf8Length(int rune) => rune < 0x80
    ? 1
    : rune < 0x800
    ? 2
    : rune < 0x10000
    ? 3
    : 4;

/// Runs one of Google's Text to Speech calls, whose messages it frees with
/// its own function.
void _checked(int Function(Pointer<Pointer<Char>> error) call) =>
    checkNativeStatus(call, tts.freeError);
