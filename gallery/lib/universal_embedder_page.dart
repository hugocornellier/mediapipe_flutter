import 'dart:async';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mediapipe_retrieval/mediapipe_retrieval.dart';

import 'catalog.dart';
import 'embed_page.dart' show embedSamples;
import 'live/still_image.dart' show pickStillImage;
import 'live/task_settings.dart';
import 'live/task_settings_panel.dart';
import 'main.dart' show GalleryAssets;
import 'ui/components.dart';
import 'ui/design.dart';
import 'ui/workspace.dart';

/// The similarity the journey test reads.
const universalSimilarityKey = ValueKey('universal-similarity-value');

/// What one of the two inputs holds.
enum UniversalInputKind {
  text('Text'),
  image('Image');

  const UniversalInputKind(this.label);
  final String label;
}

/// Universal Embedder on two inputs, each a text or an image, and the cosine
/// similarity of their embeddings in Google's one multimodal space. Google's
/// 388 MB EmbeddingGemma 2 model downloads on first use.
class UniversalEmbedderPage extends StatefulWidget {
  const UniversalEmbedderPage({
    super.key,
    required this.task,
    required this.platform,
    this.imagePicker,
    this.onOpenMenu,
  });

  final GalleryTask task;
  final TaskPlatform platform;

  /// Lets device tests upload a fixture through the real Upload buttons.
  final Future<XFile?> Function()? imagePicker;
  final VoidCallback? onOpenMenu;

  @override
  State<UniversalEmbedderPage> createState() => _UniversalEmbedderPageState();
}

/// One of the two inputs.
final class _Slot {
  _Slot(this.kind, {String text = '', this.sample})
    : controller = TextEditingController(text: text);

  UniversalInputKind kind;
  final TextEditingController controller;

  /// The chosen sample's file, or null for an upload.
  String? sample;

  /// The encoded image, which the task embeds as it is.
  Uint8List? bytes;

  /// Bumped per choice, so a slow load never replaces a newer choice.
  int choice = 0;
}

class _UniversalEmbedderPageState extends State<UniversalEmbedderPage> {
  static const _id = 'universal';

  late final List<Delegate> _delegates = widget.task
      .capabilities(widget.platform)
      .supportedDelegates
      .toList();
  late final Delegate _delegate = preferredDelegate(_delegates);
  late final TaskSettingValues _values = TaskSettingValues(
    widget.task.runtimeId,
  );
  late final List<TaskSetting> _settings =
      taskSettings[widget.task.runtimeId] ?? const [];

  /// A sentence and the photo it describes, so the page opens on a
  /// cross-modal comparison.
  final _slots = [
    _Slot(
      UniversalInputKind.text,
      text: 'A dog running across the grass with a ball.',
    ),
    _Slot(UniversalInputKind.image, sample: 'dog.jpg'),
  ];

  UniversalEmbedder? _embedder;
  Future<void> _operations = Future.value();
  int _comparison = 0;
  bool _busy = false;
  double? _similarity;
  int? _dimensions;
  double? _milliseconds;
  String? _error;
  String? _modelStatus;

  /// Bumped on every rebuild, so the settings sheet redraws with the page.
  final _revision = ValueNotifier<int>(0);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _revision.value++;
  }

  @override
  void initState() {
    super.initState();
    for (final (index, slot) in _slots.indexed) {
      if (slot.sample case final sample?) unawaited(_choose(index, sample));
    }
  }

  @override
  void dispose() {
    _comparison++;
    _close();
    for (final slot in _slots) {
      slot.controller.dispose();
    }
    _revision.dispose();
    super.dispose();
  }

  Future<void> _choose(int index, String sample) async {
    final slot = _slots[index];
    final choice = ++slot.choice;
    setState(() => slot.sample = sample);
    try {
      final data = await rootBundle.load('assets/samples/$sample');
      if (!mounted || choice != slot.choice) return;
      setState(() {
        slot.bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
      });
    } on Object catch (error) {
      if (mounted && choice == slot.choice) setState(() => _error = '$error');
    }
  }

  Future<void> _upload(int index) async {
    final slot = _slots[index];
    try {
      final file = await (widget.imagePicker?.call() ?? pickStillImage());
      if (file == null) return;
      final choice = ++slot.choice;
      final bytes = await file.readAsBytes();
      if (!mounted || choice != slot.choice) return;
      setState(() {
        slot.sample = null;
        slot.bytes = bytes;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<UniversalEmbedder> _open() async {
    if (_embedder case final embedder?) return embedder;
    setState(
      () => _modelStatus =
          'Loading ${widget.task.modelFile}; the first run downloads it '
          '(388 MB).',
    );
    try {
      return _embedder = await UniversalEmbedder.create(
        UniversalEmbedderOptions(
          modelPath: await GalleryAssets.downloadedModelPath(widget.task.model),
          delegate: _delegate,
          l2Normalize: _values.on('l2Normalize'),
        ),
      );
    } finally {
      if (mounted) setState(() => _modelStatus = null);
    }
  }

  /// Embeds both inputs and compares them.
  void _compare() {
    final comparison = ++_comparison;
    setState(() {
      _busy = true;
      _error = null;
    });
    _operations = _operations.then((_) async {
      if (!mounted || comparison != _comparison) return;
      try {
        final embedder = await _open();
        final clock = Stopwatch()..start();
        final embeddings = <Embedding>[];
        for (final slot in _slots) {
          final result = switch (slot.kind) {
            UniversalInputKind.text => await embedder.embedText(
              slot.controller.text,
            ),
            UniversalInputKind.image => await embedder.embedImage(
              slot.bytes ?? (throw StateError('Choose an image first.')),
            ),
          };
          embeddings.add(result.embeddings.first);
        }
        final similarity = UniversalEmbedder.cosineSimilarity(
          embeddings[0],
          embeddings[1],
        );
        clock.stop();
        if (!mounted || comparison != _comparison) return;
        setState(() {
          _similarity = similarity;
          _dimensions = embeddings.first.length;
          _milliseconds = clock.elapsedMicroseconds / 1000;
          _busy = false;
        });
      } on Object catch (error) {
        if (!mounted || comparison != _comparison) return;
        setState(() {
          _similarity = null;
          _error = '$error';
          _busy = false;
        });
      }
    });
  }

  void _close() {
    _operations = _operations.then((_) async {
      final embedder = _embedder;
      _embedder = null;
      try {
        await embedder?.dispose();
      } on Object catch (error) {
        if (mounted) setState(() => _error = '$error');
      }
    });
  }

  void _setSetting(String key, Object value) {
    setState(() => _values[key] = value);
    _close();
    if (_similarity != null) _compare();
  }

  Widget _panel() => ListenableBuilder(
    listenable: _revision,
    builder: (context, _) => TaskSettingsPanel(
      settings: _settings,
      values: _values,
      delegates: _delegates,
      delegate: _delegate,
      enabled: !_busy,
      onChanged: _setSetting,
      onDelegate: (_) {},
      models: const [],
      model: null,
      uploaded: null,
      modelStatus: _modelStatus,
      onModel: (_) {},
      onUpload: null,
      bundledModel: widget.task.modelFile,
      standardModel: 'EmbeddingGemma 2 (text and vision)',
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = GalleryColors.of(context);
    final ms = _milliseconds;
    return TaskWorkspace(
      title: widget.task.title,
      onOpenMenu: widget.onOpenMenu,
      settings: _panel(),
      children: [
        TaskToolbar(task: widget.task),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 640) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _slot(c, 0)),
                  const SizedBox(width: 20),
                  Expanded(child: _slot(c, 1)),
                ],
              );
            }
            return Column(
              children: [_slot(c, 0), const SizedBox(height: 18), _slot(c, 1)],
            );
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            PrimaryButton(
              key: const ValueKey('$_id-compare'),
              icon: LucideIcons.play,
              label: 'Compare',
              onPressed: _busy ? null : _compare,
            ),
            const SizedBox(width: 16),
            if (_busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (ms != null)
              Text(
                'Done in ${ms.toStringAsFixed(1)} ms',
                style: TextStyle(color: c.muted, fontSize: Sizes.xs),
              ),
          ],
        ),
        if (_modelStatus case final status?) ...[
          const SizedBox(height: 12),
          Text(
            status,
            style: TextStyle(color: c.muted, fontSize: Sizes.xs),
          ),
        ],
        const SizedBox(height: 16),
        FeedStatus(
          parts: [
            if (_dimensions case final dimensions?) '$dimensions dimensions',
            if (ms != null) 'Inference ${ms.toStringAsFixed(1)} ms',
          ],
          delegate: _similarity == null ? null : 'CPU',
        ),
        if (_error case final error?)
          Semantics(
            identifier: '$_id-error',
            container: true,
            child: Padding(
              key: const ValueKey('$_id-error'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                error,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: Sizes.sm,
                ),
              ),
            ),
          ),
        _similarityCard(c),
      ],
    );
  }

  /// One input: its kind, and the text field or the sample chips, Upload
  /// button and picture.
  Widget _slot(GalleryColors c, int index) {
    final slot = _slots[index];
    final number = index + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Eyebrow('Input $number')),
            Segmented<UniversalInputKind>(
              semanticsIdentifier: '$_id-$number-kind',
              segments: [
                for (final kind in UniversalInputKind.values)
                  (
                    value: kind,
                    label: kind.label,
                    icon: null,
                    key: ValueKey('$_id-$number-${kind.name}'),
                  ),
              ],
              selected: slot.kind,
              onChanged: (kind) => setState(() => slot.kind = kind),
            ),
          ],
        ),
        const SizedBox(height: 10),
        switch (slot.kind) {
          UniversalInputKind.text => TextField(
            key: ValueKey('$_id-$number-text'),
            controller: slot.controller,
            minLines: 3,
            maxLines: 6,
            style: TextStyle(color: c.text, fontSize: Sizes.md, height: 1.45),
            decoration: const InputDecoration(labelText: 'Text'),
          ),
          UniversalInputKind.image => _image(c, index),
        },
      ],
    );
  }

  Widget _image(GalleryColors c, int index) {
    final slot = _slots[index];
    final number = index + 1;
    final bytes = slot.bytes;
    final label = embedSamples
        .where((sample) => sample.file == slot.sample)
        .firstOrNull
        ?.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Segmented<String>(
                    semanticsIdentifier: '$_id-$number-samples',
                    segments: [
                      for (final sample in embedSamples)
                        (
                          value: sample.file,
                          label: sample.label,
                          icon: null,
                          key: ValueKey(
                            '$_id-$number-${sample.label.toLowerCase()}',
                          ),
                        ),
                    ],
                    selected: slot.sample,
                    onChanged: (sample) => unawaited(_choose(index, sample)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Semantics(
              identifier: '$_id-$number-upload',
              container: true,
              child: OutlineButton(
                key: ValueKey('$_id-$number-upload'),
                icon: LucideIcons.upload,
                label: 'Upload',
                tooltip: 'Upload image $number',
                onPressed: () => unawaited(_upload(index)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          height: math.min(MediaQuery.sizeOf(context).height * .3, 260),
          decoration: BoxDecoration(
            color: const Color(0xFF090B0B),
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(Sizes.radius),
          ),
          clipBehavior: Clip.antiAlias,
          child: bytes == null
              ? const Center(child: CircularProgressIndicator())
              : Image.memory(
                  bytes,
                  key: ValueKey('$_id-$number-image'),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  semanticLabel: 'Image $number: ${label ?? 'uploaded'}',
                ),
        ),
      ],
    );
  }

  Widget _similarityCard(GalleryColors c) {
    final value = _similarity?.toStringAsFixed(4);
    return Semantics(
      identifier: 'universal-similarity',
      container: true,
      label: 'Cosine similarity ${value ?? '--'}',
      excludeSemantics: true,
      child: SurfaceCard(
        child: Column(
          children: [
            const Eyebrow('Cosine similarity'),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: Center(
                child: value == null && _busy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : AnimatedOpacity(
                        opacity: _busy ? .4 : 1,
                        duration: const Duration(milliseconds: 150),
                        child: Text(
                          value ?? '--',
                          key: universalSimilarityKey,
                          style: TextStyle(
                            color: c.teal,
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
