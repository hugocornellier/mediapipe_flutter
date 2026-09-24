import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_core/mediapipe_flutter_core.dart'
    show ClassifierOptions, EmbedderOptions;
import 'package:mediapipe_flutter_text/mediapipe_flutter_text.dart';
import 'package:mediapipe_flutter_vision/capabilities.dart';

import 'catalog.dart';
import 'live/task_models.dart';
import 'live/task_settings.dart';
import 'live/task_settings_panel.dart';

/// A text task on typed input, laid out as the live demos are: the input and
/// its results beside the same settings panel, with MediaPipe Studio's
/// settings and model selection.
class TextPage extends StatefulWidget {
  const TextPage({super.key, required this.task});

  final GalleryTask task;

  @override
  State<TextPage> createState() => _TextPageState();
}

/// One line of a result: a label and its score, drawn as a bar.
typedef _Row = ({String label, double score});

class _TextPageState extends State<TextPage> {
  late final String _id = widget.task.runtimeId;
  late final TaskSettingValues _values = TaskSettingValues(_id);
  late final List<TaskSetting> _settings = taskSettings[_id] ?? const [];
  late final List<TaskModel> _models = taskModels[_id] ?? const [];
  late final _first = TextEditingController(text: _samples[_id]!.$1);
  late final _second = TextEditingController(text: _samples[_id]!.$2);

  TaskModel? _model;
  String? _uploaded;
  Uint8List? _modelBytes;
  String? _modelStatus;

  /// The open task, rebuilt when a setting or the model changes.
  Object? _task;
  bool _busy = false;
  String? _error;
  List<_Row>? _rows;
  double? _similarity;
  double? _milliseconds;

  /// Bumped on every rebuild, so the settings sheet redraws with the page.
  final _revision = ValueNotifier<int>(0);

  static const _samples = <String, (String, String)>{
    'text_classifier': ('I loved this movie, it was wonderful!', ''),
    'language_detector': ('Merci beaucoup pour votre aide.', ''),
    'text_embedder': (
      'The weather is lovely today.',
      "It's a beautiful sunny day.",
    ),
  };

  bool get _embedder => _id == 'text_embedder';

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _revision.value++;
  }

  @override
  void dispose() {
    unawaited(_close());
    _first.dispose();
    _second.dispose();
    _revision.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    final task = _task;
    _task = null;
    switch (task) {
      case TextClassifier task:
        await task.dispose();
      case LanguageDetector task:
        await task.dispose();
      case TextEmbedder task:
        await task.dispose();
    }
  }

  Future<Uint8List> _bytes() async {
    if (_modelBytes case final bytes?) return bytes;
    final data = await rootBundle.load('assets/models/${widget.task.model}');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<Object> _open() async {
    if (_task case final task?) return task;
    final bytes = await _bytes();
    final classifier = ClassifierOptions(
      maxResults: _values.count('maxResults'),
      scoreThreshold: _values.share('scoreThreshold'),
    );
    return _task = switch (_id) {
      'text_classifier' => await TextClassifier.create(
        TextClassifierOptions.fromAssetBuffer(
          bytes,
          classifierOptions: classifier,
        ),
      ),
      'language_detector' => await LanguageDetector.create(
        LanguageDetectorOptions.fromAssetBuffer(
          bytes,
          classifierOptions: classifier,
        ),
      ),
      _ => await TextEmbedder.create(
        TextEmbedderOptions.fromAssetBuffer(
          bytes,
          embedderOptions: EmbedderOptions(
            l2Normalize: _values.on('l2Normalize'),
            quantize: _values.on('quantize'),
          ),
        ),
      ),
    };
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final task = await _open();
      final clock = Stopwatch()..start();
      switch (task) {
        case TextClassifier task:
          final result = await task.classify(_first.text);
          _rows = [
            for (final category in result.classifications.first.categories)
              (label: category.categoryName ?? '', score: category.score),
          ];
        case LanguageDetector task:
          final result = await task.detect(_first.text);
          _rows = [
            for (final prediction in result.predictions)
              (label: prediction.languageCode, score: prediction.probability),
          ];
        case TextEmbedder task:
          final a = await task.embed(_first.text);
          final b = await task.embed(_second.text);
          _similarity = await task.cosineSimilarity(
            a.embeddings.first,
            b.embeddings.first,
          );
      }
      _milliseconds = clock.elapsedMicroseconds / 1000;
    } on Object catch (error) {
      _error = '$error';
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Rebuilds the task on the next run with the changed settings or model.
  Future<void> _reset() async {
    await _close();
    if (mounted) await _run();
  }

  void _setSetting(String key, Object value) {
    setState(() => _values[key] = value);
    unawaited(_reset());
  }

  Future<void> _chooseModel(TaskModel? model) async {
    if (model == null) {
      setState(() {
        _model = null;
        _uploaded = null;
        _modelBytes = null;
        _modelStatus = null;
      });
      unawaited(_reset());
      return;
    }
    setState(() => _modelStatus = 'Downloading ${model.name}…');
    try {
      final bytes = await downloadModel(model);
      if (!mounted) return;
      setState(() {
        _model = model;
        _uploaded = null;
        _modelBytes = bytes;
        _modelStatus = null;
      });
      unawaited(_reset());
    } on Object catch (error) {
      if (mounted) setState(() => _modelStatus = '$error');
    }
  }

  Future<void> _upload() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'MediaPipe models', extensions: ['tflite', 'task']),
        ],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _model = null;
        _uploaded = file.name;
        _modelBytes = bytes;
        _modelStatus = null;
      });
      unawaited(_reset());
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
      models: _models,
      model: _model,
      uploaded: _uploaded,
      modelStatus: _modelStatus,
      onModel: _chooseModel,
      onUpload: _upload,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
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
                TextField(
                  controller: _first,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: _embedder ? 'First text' : 'Text',
                  ),
                ),
                if (_embedder) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _second,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Second text',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _run,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(_embedder ? 'Compare' : 'Run'),
                  ),
                ),
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
                  if (_embedder && _similarity != null)
                    Text(
                      'Cosine similarity: ${_similarity!.toStringAsFixed(4)}',
                      style: theme.textTheme.titleMedium,
                    ),
                  if (!_embedder)
                    for (final row in _rows ?? const <_Row>[])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(row.label)),
                                Text(row.score.toStringAsFixed(3)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(value: row.score),
                          ],
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
