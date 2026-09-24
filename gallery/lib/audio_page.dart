import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_audio/mediapipe_flutter_audio.dart';
import 'package:mediapipe_flutter_vision/capabilities.dart';
import 'package:record/record.dart';

import 'catalog.dart';
import 'live/task_models.dart';
import 'live/task_settings.dart';
import 'live/task_settings_panel.dart';

/// Audio Classifier on a clip, laid out as the other demos are: the clip and
/// its results beside the same settings panel, with MediaPipe Studio's
/// settings and model selection.
class AudioPage extends StatefulWidget {
  const AudioPage({super.key, required this.task});

  final GalleryTask task;

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
  bool _busy = false;
  String? _error;
  AudioData? _audio;
  List<AudioClassification>? _chunks;
  double? _milliseconds;

  final _revision = ValueNotifier<int>(0);

  /// Microphone mode: 16 kHz mono PCM, classified one YAMNet window
  /// (0.975 s) at a time as it arrives, newest first.
  bool _microphone = false;
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _stream;
  final _pending = <double>[];
  bool _classifying = false;
  final _heard = <AudioClassification>[];
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

  /// Rebuilds the task with the changed settings or model, then reruns.
  Future<void> _reset() async {
    final task = _task;
    _task = null;
    await task?.dispose();
    if (mounted && !_microphone) await _run();
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
          XTypeGroup(label: 'WAV audio', extensions: ['wav']),
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
          XTypeGroup(label: 'MediaPipe models', extensions: ['tflite', 'task']),
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
      delegates: const [VisionDelegate.cpu],
      delegate: VisionDelegate.cpu,
      enabled: !_busy,
      onChanged: _setSetting,
      onDelegate: (_) {},
      models: const [],
      model: null,
      uploaded: _uploadedModel,
      modelStatus: _modelStatus,
      onModel: _chooseModel,
      onUpload: _uploadModel,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final audio = _audio;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task.title),
        actions: [
          if (!wide)
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'Settings',
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (context) => SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.6,
                  child: _panel(),
                ),
              ),
            ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.audio_file),
                      label: Text('Clips'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.mic),
                      label: Text('Microphone'),
                    ),
                  ],
                  selected: {_microphone},
                  onSelectionChanged: _busy
                      ? null
                      : (selection) => _setMicrophone(selection.first),
                ),
                const SizedBox(height: 16),
                if (_microphone)
                  Text(
                    _stream == null
                        ? 'Starting the microphone…'
                        : 'Listening: each 0.975 s window is classified as it '
                              'arrives, newest first.',
                    style: theme.textTheme.bodySmall,
                  )
                else ...[
                  Text('Audio clip', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final MapEntry(key: file, value: label)
                          in _clips.entries)
                        ChoiceChip(
                          label: Text(label),
                          selected: _uploadedClip == null && _clip == file,
                          onSelected: _busy
                              ? null
                              : (_) {
                                  setState(() {
                                    _clip = file;
                                    _uploadedClip = null;
                                  });
                                  unawaited(_run());
                                },
                        ),
                      ChoiceChip(
                        avatar: const Icon(Icons.upload, size: 18),
                        label: Text(_uploadedClip?.name ?? 'Upload WAV'),
                        selected: _uploadedClip != null,
                        onSelected: _busy ? null : (_) => _uploadClip(),
                      ),
                    ],
                  ),
                  if (audio != null && !_microphone)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${(audio.samples.length / audio.channels / audio.sampleRate).toStringAsFixed(2)} s · '
                        '${audio.sampleRate.round()} Hz · '
                        '${audio.channels} channel${audio.channels == 1 ? '' : 's'}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
                const SizedBox(height: 20),
                if (_busy) const LinearProgressIndicator(),
                if (_error case final error?)
                  Text(error, style: TextStyle(color: theme.colorScheme.error))
                else ...[
                  if (_milliseconds case final ms?)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Done in ${ms.toStringAsFixed(1)} ms',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  for (final chunk
                      in _microphone
                          ? _heard
                          : _chunks ?? const <AudioClassification>[])
                    Card.outlined(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${(chunk.timestampMs / 1000).toStringAsFixed(2)} s',
                              style: theme.textTheme.labelLarge,
                            ),
                            const SizedBox(height: 6),
                            if (chunk.categories.isEmpty)
                              Text(
                                'Nothing above the score threshold.',
                                style: theme.textTheme.bodySmall,
                              ),
                            for (final category in chunk.categories)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(category.name ?? ''),
                                        ),
                                        Text(category.score.toStringAsFixed(3)),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    LinearProgressIndicator(
                                      value: category.score,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          if (wide) ...[
            const VerticalDivider(width: 1),
            SizedBox(width: 340, child: _panel()),
          ],
        ],
      ),
    );
  }
}
