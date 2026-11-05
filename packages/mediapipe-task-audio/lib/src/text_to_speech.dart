import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/platform_interface.dart';

import 'capabilities.dart';
import 'native_tasks.dart';
import 'speech_runners.dart';
import 'speech_types.dart';

/// Google's Text to Speech (for example Phonon): speech from text, as one
/// utterance or chunk by chunk, with when each word is spoken.
///
/// Google's native runtime serves it on 64-bit Android, iOS, macOS, Linux
/// and Windows, loading the model and synthesizing on a worker isolate, and
/// its browser runtime on a web worker.
///
/// ```dart
/// final task = await TextToSpeech.create(
///   TextToSpeechOptions(model: AudioModels.phonon),
/// );
/// final speech = await task.synthesize('Hello there.');
/// play(speech.samples, speech.sampleRateHz);
/// await task.dispose();
/// ```
///
/// Calls run one at a time, in call order; a stream holds the task until
/// it ends or its listener cancels. `dispose()` waits for work already
/// accepted and is idempotent.
final class TextToSpeech {
  TextToSpeech._(this._runner, this.delegate);

  final TextToSpeechRunner _runner;
  Future<void>? _disposing;

  /// The processor the task runs on, fixed at creation.
  final Delegate delegate;

  /// Resolves the model and opens Google's task; the model loads before
  /// this completes.
  static Future<TextToSpeech> create(TextToSpeechOptions options) async {
    requireDelegate(await queryTextToSpeechCapabilities(), options.delegate);
    await resolveTaskModel(options);
    try {
      return TextToSpeech._(
        await openNativeTextToSpeech(options),
        options.delegate,
      );
    } catch (error) {
      throw taskException(error);
    }
  }

  /// The voices in the loaded model.
  Future<List<TextToSpeechVoice>> listVoices() async {
    _check();
    return _runner.listVoices();
  }

  /// [text] spoken as one utterance, in [voiceId] and [locale], or the
  /// options' defaults where null.
  Future<TextToSpeechResult> synthesize(
    String text, {
    String? voiceId,
    String? locale,
  }) async {
    _check();
    return _runner.synthesize(text, voiceId, locale);
  }

  /// [text] spoken chunk by chunk, each as soon as its clause is
  /// synthesized, so playback can start before the rest is ready. Word
  /// timestamps index into [text] and are timed from the stream's start.
  ///
  /// One subscription. Cancelling it stops Google's stream once the chunk
  /// in progress is done. A failure arrives as a [TaskException] and closes
  /// the stream.
  Stream<TextToSpeechResult> synthesizeStream(
    String text, {
    String? voiceId,
    String? locale,
  }) {
    _check();
    return _runner.synthesizeStream(text, voiceId, locale);
  }

  /// Finishes accepted work and releases Google's task. Repeated calls
  /// return the same completion; any other call afterwards fails with
  /// [StateError].
  Future<void> dispose() => _disposing ??= _runner.dispose();

  void _check() {
    if (_disposing != null) {
      throw StateError('TextToSpeech has been disposed.');
    }
  }
}
