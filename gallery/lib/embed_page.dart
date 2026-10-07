import 'dart:async';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';

import 'catalog.dart';
import 'live/still_image.dart';
import 'live/task_models.dart';
import 'live/task_settings.dart';
import 'live/task_settings_panel.dart';
import 'ui/components.dart';
import 'ui/design.dart';
import 'ui/workspace.dart';

/// The photos Google's Image Embedding demo offers for either image, with
/// the labels its chips show.
const embedSamples = [
  (label: 'Dog', file: 'dog.jpg'),
  (label: 'Cat', file: 'cat.png'),
  (label: 'Elephant', file: 'elephant.png'),
];

/// Image Embedder as Google's demo shows it: two still images, each a sample
/// or an upload, and the cosine similarity of their embeddings. Choosing an
/// image, the model, the delegate or a setting compares them again.
class EmbedPage extends StatefulWidget {
  const EmbedPage({
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
  State<EmbedPage> createState() => _EmbedPageState();
}

/// One of the two images.
final class _Slot {
  _Slot(this.sample);

  /// The chosen sample's file, or null for an upload.
  String? sample;

  /// The encoded image on screen, and the pixels the task embeds.
  Uint8List? bytes;
  VisionImage? input;

  /// Bumped per choice, so a slow decode never replaces a newer choice.
  int choice = 0;
}

class _EmbedPageState extends State<EmbedPage> {
  static const _id = 'image-embedder';

  late final List<Delegate> _delegates =
      widget.task.capabilities(widget.platform).supportedDelegates.toList()
        ..sort((a, b) => a.index.compareTo(b.index));
  late Delegate _delegate = preferredDelegate(_delegates);
  late final TaskSettingValues _values = TaskSettingValues(
    widget.task.runtimeId,
  );
  late final List<TaskSetting> _settings =
      taskSettings[widget.task.runtimeId] ?? const [];
  late final List<TaskModel> _models =
      taskModels[widget.task.runtimeId] ?? const [];
  TaskModel? _model;
  String? _uploaded;
  Uint8List? _modelBytes;
  String? _modelStatus;

  /// Dog and Cat, so the page opens with a comparison on screen.
  final _slots = [_Slot('dog.jpg'), _Slot('cat.png')];

  /// The open task, kept between comparisons and rebuilt when the model, the
  /// delegate or a setting changes.
  ImageEmbedder? _embedder;

  /// Opening, comparing and closing the task, one at a time in order.
  Future<void> _operations = Future.value();

  /// Bumped per comparison, so only the newest one reports.
  int _comparison = 0;
  bool _busy = false;
  double? _similarity;
  int? _dimensions;
  double? _milliseconds;
  Delegate? _ranOn;
  String? _error;

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
      unawaited(_choose(index, slot.sample!));
    }
  }

  @override
  void dispose() {
    _comparison++;
    _close();
    _revision.dispose();
    super.dispose();
  }

  /// Shows one of the samples as the image at [index].
  Future<void> _choose(int index, String sample) async {
    final slot = _slots[index];
    if (slot.sample == sample && slot.input != null) return;
    final choice = ++slot.choice;
    // The chip follows the tap at once; the picture follows once decoded.
    setState(() => slot.sample = sample);
    try {
      final data = await rootBundle.load('assets/samples/$sample');
      await _show(
        slot,
        choice,
        sample,
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } on Object catch (error) {
      if (mounted && choice == slot.choice) setState(() => _error = '$error');
    }
  }

  /// An image of the user's own as the image at [index].
  Future<void> _upload(int index) async {
    final slot = _slots[index];
    try {
      final file = await (widget.imagePicker?.call() ?? pickStillImage());
      if (file == null) return;
      final choice = ++slot.choice;
      await _show(slot, choice, null, await file.readAsBytes());
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _show(
    _Slot slot,
    int choice,
    String? sample,
    Uint8List bytes,
  ) async {
    final still = await decodeStillImage(bytes);
    if (!mounted || choice != slot.choice) return;
    setState(() {
      slot.sample = sample;
      slot.bytes = bytes;
      slot.input = still.input;
    });
    _compare();
  }

  /// Embeds both images and compares them, once both have decoded.
  void _compare() {
    final first = _slots[0].input;
    final second = _slots[1].input;
    if (first == null || second == null) return;
    final comparison = ++_comparison;
    setState(() => _busy = true);
    _operations = _operations.then((_) async {
      if (!mounted || comparison != _comparison) return;
      try {
        final embedder = await _open();
        final clock = Stopwatch()..start();
        final a = (await embedder.embed(first)).embeddings.first;
        final b = (await embedder.embed(second)).embeddings.first;
        final similarity = ImageEmbedder.cosineSimilarity(a, b);
        clock.stop();
        if (!mounted || comparison != _comparison) return;
        setState(() {
          _similarity = similarity;
          _dimensions =
              a.floatEmbedding?.length ?? a.quantizedEmbedding?.length;
          _milliseconds = clock.elapsedMicroseconds / 1000;
          _ranOn = _delegate;
          _error = null;
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

  Future<ImageEmbedder> _open() async {
    if (_embedder case final embedder?) return embedder;
    final bytes = _modelBytes;
    Future<ImageEmbedder> create(Delegate delegate) => ImageEmbedder.create(
      ImageEmbedderOptions(
        delegate: delegate,
        model: bytes == null ? widget.task.model : null,
        modelBytes: bytes,
        runningMode: RunningMode.image,
        l2Normalize: _values.on('l2Normalize'),
        quantize: _values.on('quantize'),
      ),
    );
    try {
      return _embedder = await create(_delegate);
    } on Object {
      // GPU is only the default; a platform that refuses it gets CPU.
      if (_delegate != Delegate.gpu) rethrow;
      if (mounted) setState(() => _delegate = Delegate.cpu);
      return _embedder = await create(Delegate.cpu);
    }
  }

  /// Releases the task once whatever is running has finished, so the next
  /// comparison opens it with the current model, delegate and settings.
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

  void _reopen() {
    _close();
    _compare();
  }

  void _setSetting(String key, Object value) {
    setState(() => _values[key] = value);
    _reopen();
  }

  void _setDelegate(Delegate delegate) {
    if (delegate == _delegate) return;
    setState(() => _delegate = delegate);
    _reopen();
  }

  /// Downloads and verifies an official model before the task is rebuilt
  /// with it, so a failed download leaves the running model in place.
  Future<void> _chooseModel(TaskModel? model) async {
    if (model == null) {
      setState(() {
        _model = null;
        _uploaded = null;
        _modelBytes = null;
        _modelStatus = null;
      });
      _reopen();
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
      _reopen();
    } on Object catch (error) {
      if (mounted) setState(() => _modelStatus = '$error');
    }
  }

  /// A model file of the user's own, as MediaPipe Studio's Upload.
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
      if (!mounted) return;
      setState(() {
        _model = null;
        _uploaded = file.name;
        _modelBytes = bytes;
        _modelStatus = null;
      });
      _reopen();
    } on Object catch (error) {
      if (mounted) setState(() => _modelStatus = '$error');
    }
  }

  Widget _panel() => ListenableBuilder(
    listenable: _revision,
    builder: (context, _) => TaskSettingsPanel(
      settings: _settings,
      values: _values,
      delegates: _delegates,
      delegate: _delegate,
      // Every change queues behind the comparison running, so nothing
      // needs to wait for it.
      enabled: true,
      onChanged: _setSetting,
      onDelegate: _setDelegate,
      models: _models,
      model: _model,
      uploaded: _uploaded,
      modelStatus: _modelStatus,
      onModel: _chooseModel,
      onUpload: _uploadModel,
      bundledModel: widget.task.modelFile,
      standardModel: standardModelNames[widget.task.runtimeId] ?? 'Standard',
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = GalleryColors.of(context);
    final screen = MediaQuery.sizeOf(context);
    final ms = _milliseconds;
    return TaskWorkspace(
      title: widget.task.title,
      onOpenMenu: widget.onOpenMenu,
      settings: _panel(),
      children: [
        TaskToolbar(task: widget.task),
        LayoutBuilder(
          builder: (context, constraints) {
            // Side by side, as Google's demo shows them, while each image's
            // chips still fit beside its Upload button.
            if (constraints.maxWidth >= 540) {
              final width = (constraints.maxWidth - 20) / 2;
              final height = math.min(width, 340.0);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _slot(c, 0, height)),
                  const SizedBox(width: 20),
                  Expanded(child: _slot(c, 1, height)),
                ],
              );
            }
            // Stacked, short enough that a phone shows both images and
            // the similarity together.
            final height = (screen.height * .19).clamp(130.0, 240.0);
            return Column(
              children: [
                _slot(c, 0, height),
                const SizedBox(height: 18),
                _slot(c, 1, height),
              ],
            );
          },
        ),
        FeedStatus(
          parts: [
            if (_dimensions case final dimensions?) '$dimensions dimensions',
            if (ms != null) 'Inference ${ms.toStringAsFixed(1)} ms',
          ],
          delegate: switch (_ranOn) {
            Delegate.gpu => 'GPU',
            Delegate.cpu => 'CPU',
            _ => null,
          },
        ),
        if (_error case final error?)
          Padding(
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
        _similarityCard(c),
      ],
    );
  }

  /// One image: its sample chips, its Upload button and the picture.
  Widget _slot(GalleryColors c, int index, double height) {
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
        Eyebrow('Image $number'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                // A narrow column shrinks the chips rather than wrapping.
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
          height: height,
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
                  // Keeps the last picture up while the next one decodes.
                  gaplessPlayback: true,
                  semanticLabel: 'Image $number: ${label ?? 'uploaded'}',
                ),
        ),
      ],
    );
  }

  /// Google's result card: the similarity, large, under its label.
  Widget _similarityCard(GalleryColors c) {
    final value = _similarity?.toStringAsFixed(4);
    return Semantics(
      container: true,
      label: 'Cosine similarity ${value ?? '--'}',
      excludeSemantics: true,
      child: SurfaceCard(
        key: const ValueKey('$_id-similarity'),
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
                    // A comparison in progress dims the value it replaces.
                    : AnimatedOpacity(
                        opacity: _busy ? .4 : 1,
                        duration: const Duration(milliseconds: 150),
                        child: Text(
                          value ?? '--',
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
