import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mediapipe_text/mediapipe_text.dart';
import 'package:mediapipe_vision/capabilities.dart';

import 'catalog.dart';
import 'live/task_models.dart';
import 'live/task_settings.dart';
import 'live/task_settings_panel.dart';
import 'ui/components.dart';
import 'ui/design.dart';
import 'ui/workspace.dart';

/// A text task on typed input, laid out as the live demos are: the input and
/// its results beside the same settings panel, with MediaPipe Studio's
/// settings and model selection.
class TextPage extends StatefulWidget {
  const TextPage({super.key, required this.task, this.onOpenMenu});

  final GalleryTask task;
  final VoidCallback? onOpenMenu;

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
    ClassifierOptions classifier() => ClassifierOptions(
      maxResults: _values.count('maxResults'),
      scoreThreshold: _values.share('scoreThreshold'),
    );
    return _task = switch (_id) {
      'text_classifier' => await TextClassifier.create(
        TextClassifierOptions.fromAssetBuffer(
          bytes,
          classifierOptions: classifier(),
        ),
      ),
      'language_detector' => await LanguageDetector.create(
        LanguageDetectorOptions.fromAssetBuffer(
          bytes,
          classifierOptions: classifier(),
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
      bundledModel: widget.task.model,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = GalleryColors.of(context);
    final phone = MediaQuery.sizeOf(context).width < Sizes.compact;
    Widget field(TextEditingController controller, String label) => TextField(
      controller: controller,
      minLines: 3,
      maxLines: 6,
      style: TextStyle(color: c.text, fontSize: Sizes.md, height: 1.45),
      decoration: InputDecoration(labelText: label),
    );
    return TaskWorkspace(
      title: widget.task.title,
      onOpenMenu: widget.onOpenMenu,
      settings: _panel(),
      children: [
        PageHeading(
          eyebrow: '${widget.task.category.title} / Live demo',
          title: widget.task.title,
          summary: widget.task.summary,
          trailing: phone
              ? null
              : OutlineButton(
                  icon: LucideIcons.circleHelp,
                  label: 'Help',
                  tooltip: 'Help',
                  onPressed: () => showTaskHelp(context, widget.task),
                ),
        ),
        SizedBox(height: phone ? 24 : 32),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('Input'),
              const SizedBox(height: 14),
              field(_first, _embedder ? 'First text' : 'Text'),
              if (_embedder) ...[
                const SizedBox(height: 12),
                field(_second, 'Second text'),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  PrimaryButton(
                    icon: LucideIcons.play,
                    label: _embedder ? 'Compare' : 'Run',
                    onPressed: _busy ? null : _run,
                  ),
                  const SizedBox(width: 16),
                  if (_busy)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (_milliseconds case final ms?)
                    Text(
                      'Done in ${ms.toStringAsFixed(1)} ms',
                      style: TextStyle(color: c.muted, fontSize: Sizes.xs),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
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
        else if (_embedder)
          OutputCard(
            title: 'Similarity',
            count: 'cosine',
            items: [
              if (_similarity case final similarity?)
                (name: 'Cosine similarity', value: similarity),
            ],
            empty: 'Compare two texts to see how alike they are.',
          )
        else
          OutputCard(
            title: _id == 'language_detector' ? 'Languages' : 'Categories',
            count: _rows == null
                ? null
                : '${_rows!.length} result${_rows!.length == 1 ? '' : 's'}',
            items: [
              for (final row in _rows ?? const <_Row>[])
                (name: row.label, value: row.score),
            ],
            empty: 'Run the task to see its results.',
          ),
      ],
    );
  }
}
