import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mediapipe_audio/mediapipe_audio.dart';
import 'package:record/record.dart';

import 'catalog.dart';
import 'live/task_models.dart';
import 'live/task_settings.dart';
import 'live/task_settings_panel.dart';
import 'ui/components.dart';
import 'ui/design.dart';
import 'ui/workspace.dart';

/// Audio Classifier on a clip, laid out as the other demos are: the clip and
/// its results beside the same settings panel, with MediaPipe Studio's
/// settings and model selection.
class AudioPage extends StatefulWidget {
  const AudioPage({super.key, required this.task, this.onOpenMenu});

  final GalleryTask task;
  final VoidCallback? onOpenMenu;

  @override
  State<AudioPage> createState() => _AudioPageState();
}

/// Google's sample clips, bundled with the gallery on macOS.
const _clips = <String, String>{
  'speech_16000_hz_mono.wav': 'Speech (16 kHz)',
  'speech_48000_hz_mono.wav': 'Speech (48 kHz)',
  'two_heads_16000_hz_mono.wav': 'Animal sounds',
};

class _AudioPageState extends State<AudioPage> {
  late final TaskSettingValues _values = TaskSettingValues('audio_classifier');
  late final List<TaskSetting> _settings =
      taskSettings['audio_classifier'] ?? const [];

  String _clip = _clips.keys.first;
  ({String name, Uint8List bytes})? _uploadedClip;

  String? _uploadedModel;
  Uint8List? _modelBytes;
  String? _modelStatus;

  AudioClassifier? _task;
  Future<void> _resets = Future.value();
  bool _busy = false;
  String? _error;
  AudioData? _audio;
  List<AudioClassifierResult>? _chunks;
  double? _milliseconds;

  final _revision = ValueNotifier<int>(0);

  /// Microphone mode: 16 kHz mono PCM, classified one YAMNet window
  /// (0.975 s) at a time as it arrives, newest first.
  bool _microphone = false;
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _stream;
  final _pending = <double>[];
  bool _classifying = false;
  final _heard = <AudioClassifierResult>[];
  static const _rate = 16000;
  static const _window = 15600;

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _revision.value++;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    unawaited(_stopListening());
    unawaited(_task?.dispose());
    _revision.dispose();
    super.dispose();
  }

  Future<Uint8List> _asset(String path) async {
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<AudioClassifier> _open() async =>
      _task ??= await AudioClassifier.create(
        AudioClassifierOptions(
          modelBytes:
              _modelBytes ?? await _asset('assets/models/yamnet.tflite'),
          maxResults: _values.count('maxResults'),
          scoreThreshold: _values.share('scoreThreshold'),
        ),
      );

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes =
          _uploadedClip?.bytes ?? await _asset('assets/samples/$_clip');
      final audio = decodeWav(bytes);
      final task = await _open();
      final clock = Stopwatch()..start();
      final chunks = await task.classify(audio);
      _milliseconds = clock.elapsedMicroseconds / 1000;
      _audio = audio;
      _chunks = chunks;
    } on Object catch (error) {
      _error = '$error';
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Rebuilds the task with the changed settings or model, then reruns the
  /// clip, or goes on classifying the microphone with the new task. Rebuilds
  /// run one at a time: while listening the settings stay enabled, and two at
  /// once would open two tasks, keeping whichever finished last.
  Future<void> _reset() {
    final reset = _resets.then((_) => _rebuild());
    _resets = reset.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return reset;
  }

  Future<void> _rebuild() async {
    final task = _task;
    _task = null;
    await task?.dispose();
    if (!mounted) return;
    if (!_microphone) return _run();
    // Without a task, every window that arrives is dropped.
    try {
      await _open();
      if (mounted) setState(() => _error = null);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _listen() async {
    final recorder = _recorder = AudioRecorder();
    try {
      if (!await recorder.hasPermission()) {
        throw StateError('Microphone access was not granted.');
      }
      await _open();
      final stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _rate,
          numChannels: 1,
        ),
      );
      setState(() {
        _error = null;
        _heard.clear();
        _pending.clear();
      });
      _stream = stream.listen(_samples);
    } on Object catch (error) {
      await _stopListening();
      if (mounted) setState(() => _error = '$error');
    }
  }

  /// Appends little-endian 16-bit samples and classifies each full window;
  /// windows that arrive while one is being classified are dropped, as the
  /// live camera demos drop frames.
  void _samples(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      _pending.add(data.getInt16(i, Endian.little) / 32768);
    }
    if (_pending.length < _window) return;
    final window = Float32List.fromList(
      _pending.sublist(_pending.length - _window),
    );
    _pending.clear();
    final task = _task;
    if (_classifying || task == null) return;
    _classifying = true;
    final clock = Stopwatch()..start();
    task
        .classify(AudioData(samples: window, sampleRate: _rate.toDouble()))
        .then(
          (chunks) {
            if (!mounted || !_microphone) return;
            setState(() {
              _milliseconds = clock.elapsedMicroseconds / 1000;
              _heard.insertAll(0, chunks);
              if (_heard.length > 8) _heard.removeRange(8, _heard.length);
            });
          },
          onError: (Object error) {
            if (mounted) setState(() => _error = '$error');
          },
        )
        .whenComplete(() => _classifying = false);
  }

  Future<void> _stopListening() async {
    await _stream?.cancel();
    _stream = null;
    final recorder = _recorder;
    _recorder = null;
    if (recorder != null) {
      await recorder.stop();
      await recorder.dispose();
    }
  }

  Future<void> _setMicrophone(bool on) async {
    setState(() {
      _microphone = on;
      _chunks = null;
      _milliseconds = null;
    });
    if (on) {
      await _listen();
    } else {
      await _stopListening();
      await _run();
    }
  }

  void _setSetting(String key, Object value) {
    setState(() => _values[key] = value);
    unawaited(_reset());
  }

  Future<void> _uploadClip() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'WAV audio',
            extensions: ['wav'],
            uniformTypeIdentifiers: ['com.microsoft.waveform-audio'],
          ),
        ],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() => _uploadedClip = (name: file.name, bytes: bytes));
      await _run();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _chooseModel(TaskModel? model) async {
    setState(() {
      _uploadedModel = null;
      _modelBytes = null;
      _modelStatus = null;
    });
    await _reset();
  }

  Future<void> _uploadModel() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'MediaPipe models',
            extensions: ['tflite', 'task'],
            // iOS filters by type, and models have none of their own.
            uniformTypeIdentifiers: ['public.data'],
          ),
        ],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _uploadedModel = file.name;
        _modelBytes = bytes;
        _modelStatus = null;
      });
      await _reset();
    } on Object catch (error) {
      if (mounted) setState(() => _modelStatus = '$error');
    }
  }

  Widget _panel() => ListenableBuilder(
    listenable: _revision,
    builder: (context, _) => TaskSettingsPanel(
      settings: _settings,
      values: _values,
      delegates: const [Delegate.cpu],
      delegate: Delegate.cpu,
      enabled: !_busy,
      onChanged: _setSetting,
      onDelegate: (_) {},
      models: const [],
      model: null,
      uploaded: _uploadedModel,
      modelStatus: _modelStatus,
      onModel: _chooseModel,
      onUpload: _uploadModel,
      bundledModel: 'yamnet.tflite',
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = GalleryColors.of(context);
    final audio = _audio;
    final muted = TextStyle(color: c.muted, fontSize: Sizes.xs);
    final chunks = _microphone
        ? _heard
        : _chunks ?? const <AudioClassifierResult>[];
    return TaskWorkspace(
      title: widget.task.title,
      onOpenMenu: widget.onOpenMenu,
      settings: _panel(),
      children: [
        TaskToolbar(
          task: widget.task,
          leading: Segmented<bool>(
            key: const ValueKey('audio-source'),
            segments: const [
              (
                value: false,
                label: 'Clips',
                icon: LucideIcons.fileAudio,
                key: ValueKey('audio-source-clips'),
              ),
              (
                value: true,
                label: 'Microphone',
                icon: LucideIcons.mic,
                key: ValueKey('audio-source-microphone'),
              ),
            ],
            selected: _microphone,
            onChanged: _busy ? null : (on) => unawaited(_setMicrophone(on)),
          ),
        ),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow(_microphone ? 'Microphone' : 'Audio clip'),
              const SizedBox(height: 14),
              if (_microphone)
                Row(
                  children: [
                    if (_stream != null) ...[
                      const StatusDot(),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        _stream == null
                            ? 'Starting the microphone…'
                            : 'Listening: each 0.975 s window is classified '
                                  'as it arrives, newest first.',
                        style: TextStyle(color: c.soft, fontSize: Sizes.sm),
                      ),
                    ),
                  ],
                )
              else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final MapEntry(key: file, value: label)
                        in _clips.entries)
                      Segmented<bool>(
                        segments: [
                          (value: true, label: label, icon: null, key: null),
                        ],
                        selected: _uploadedClip == null && _clip == file,
                        onChanged: _busy
                            ? null
                            : (_) {
                                setState(() {
                                  _clip = file;
                                  _uploadedClip = null;
                                });
                                unawaited(_run());
                              },
                      ),
                    Segmented<bool>(
                      segments: [
                        (
                          value: true,
                          label: _uploadedClip?.name ?? 'Upload WAV',
                          icon: LucideIcons.upload,
                          key: null,
                        ),
                      ],
                      selected: _uploadedClip != null,
                      onChanged: _busy ? null : (_) => _uploadClip(),
                    ),
                  ],
                ),
                if (audio != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${(audio.samples.length / audio.channels / audio.sampleRate).toStringAsFixed(2)} s · '
                    '${audio.sampleRate.round()} Hz · '
                    '${audio.channels} channel${audio.channels == 1 ? '' : 's'}',
                    style: muted,
                  ),
                ],
              ],
            ],
          ),
        ),
        FeedStatus(
          parts: [
            if (_busy) 'Classifying…',
            if (!_busy && _milliseconds != null)
              'Done in ${_milliseconds!.toStringAsFixed(1)} ms',
          ],
          delegate: 'CPU',
        ),
        const SizedBox(height: 11),
        if (_error case final error?)
          OutputCard(
            title: 'Error',
            child: Text(
              error,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: Sizes.sm,
              ),
            ),
          )
        else
          OutputCard(
            title: _microphone ? 'Heard' : 'Sounds over time',
            count: chunks.isEmpty
                ? null
                : '${chunks.length} window${chunks.length == 1 ? '' : 's'}',
            empty: _microphone
                ? 'Waiting for the first window.'
                : 'Choose a clip to classify it.',
            child: chunks.isEmpty
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (i, chunk) in chunks.indexed) ...[
                        if (i > 0) const SizedBox(height: 22),
                        Text(
                          '${(chunk.timestampMilliseconds / 1000).toStringAsFixed(2)} s',
                          style: eyebrowStyle(context),
                        ),
                        const SizedBox(height: 12),
                        if (_categories(chunk).isEmpty)
                          Text(
                            'Nothing above the score threshold.',
                            style: muted,
                          )
                        else
                          ScoreBars([
                            for (final category in _categories(chunk))
                              (
                                name: category.categoryName ?? '',
                                value: category.score,
                              ),
                          ]),
                      ],
                    ],
                  ),
          ),
      ],
    );
  }
}

/// The first head's categories: YAMNet has one.
List<MediaPipeCategory> _categories(AudioClassifierResult chunk) =>
    chunk.classifications.isEmpty
    ? const []
    : chunk.classifications.first.categories;
