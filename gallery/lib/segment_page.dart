import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

import 'catalog.dart';
import 'main.dart';
import 'segment/editor_controller.dart';
import 'segment/mask_overlay.dart';

/// MagicTouch segmentation: drag over a subject to select it.
///
/// The editor controller and mask thresholding are the segmenter example's,
/// copied unchanged. They already coalesce in-flight requests, keep the task's
/// float mask intact, and serialise stroke edits against native work.
class SegmentPage extends StatefulWidget {
  const SegmentPage({super.key, required this.task, required this.assets});

  final GalleryTask task;
  final GalleryAssets assets;

  @override
  State<SegmentPage> createState() => _SegmentPageState();
}

class _SegmentPageState extends State<SegmentPage> {
  EditorController? _editor;
  InteractiveSegmenter? _task;
  ui.Image? _maskImage;
  String? _error;
  double _threshold = 0.5;
  int _paintedRevision = -1;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final model = await rootBundle.load(
        'assets/models/${widget.task.model}',
      );
      final task = await InteractiveSegmenter.create(
        InteractiveSegmenterOptions(
          modelBytes: model.buffer.asUint8List(
            model.offsetInBytes,
            model.lengthInBytes,
          ),
        ),
      );
      if (!mounted) {
        await task.dispose();
        return;
      }
      _task = task;
      final editor = EditorController(NativeSegmentationBackend(task))
        ..addListener(_onEditorChanged);
      _editor = editor;
      await editor.loadImage(
        VisionImage.fromFile(widget.assets.path(widget.task.sample)),
      );
      if (mounted) setState(() {});
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  void _onEditorChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_repaintMask());
  }

  Future<void> _repaintMask() async {
    final mask = _editor?.mask;
    if (mask == null) {
      _maskImage?.dispose();
      _maskImage = null;
      return;
    }
    // Rebuilding the image on every notification would thrash; the editor only
    // produces a new mask when a stroke completes.
    final revision = Object.hash(mask, _threshold);
    if (revision == _paintedRevision) return;
    _paintedRevision = revision;
    final rgba = maskRgba(mask.confidence, _threshold);
    final image = await _decode(rgba, mask.width, mask.height);
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() {
      _maskImage?.dispose();
      _maskImage = image;
    });
  }

  Future<ui.Image> _decode(Uint8List rgba, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  @override
  void dispose() {
    _editor?.removeListener(_onEditorChanged);
    unawaited(_editor?.close());
    unawaited(_task?.dispose());
    _maskImage?.dispose();
    super.dispose();
  }

  /// A lasso stroke is discarded below three points, so a tap does nothing in
  /// that mode. Say which gesture the selected tool expects.
  static String _hintFor(SegmentationBrushMode? brush) => switch (brush) {
    SegmentationBrushMode.negative => 'Tap or drag over an area to exclude it.',
    SegmentationBrushMode.lasso => 'Draw a shape around a subject to select it.',
    _ => 'Tap or drag over a subject to include it.',
  };

  SegmentationPoint? _pointFor(Offset local, Size size) {
    if (size.width <= 0 || size.height <= 0) return null;
    final x = (local.dx / size.width).clamp(0.0, 1.0);
    final y = (local.dy / size.height).clamp(0.0, 1.0);
    return SegmentationPoint(x: x, y: y);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editor = _editor;
    final error = _error ?? editor?.error;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo stroke',
            onPressed: editor?.canUndo ?? false ? () => editor!.undo() : null,
          ),
          IconButton(
            icon: const Icon(Icons.layers_clear),
            tooltip: 'Clear selection',
            // clear() reloads the image, which drops every stroke and the mask.
            onPressed: editor != null && editor.ready && editor.canUndo
                ? () => unawaited(editor.clear())
                : null,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.black,
              width: double.infinity,
              child: error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          error,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    )
                  : editor == null || !editor.ready
                      ? const Center(child: CircularProgressIndicator())
                      : Center(
                          child: LayoutBuilder(
                            builder: (context, constraints) => GestureDetector(
                              onPanStart: (details) {
                                final point = _pointFor(
                                  details.localPosition,
                                  constraints.biggest,
                                );
                                if (point != null) editor.begin(point);
                              },
                              onPanUpdate: (details) {
                                final point = _pointFor(
                                  details.localPosition,
                                  constraints.biggest,
                                );
                                if (point != null) editor.extend(point);
                              },
                              onPanEnd: (_) => editor.end(),
                              // A single point is never a valid lasso, so let
                              // taps fall through rather than silently drop.
                              onTapUp: editor.brush == SegmentationBrushMode.lasso
                                  ? null
                                  : (details) {
                                      final point = _pointFor(
                                        details.localPosition,
                                        constraints.biggest,
                                      );
                                      if (point == null) return;
                                      editor
                                        ..begin(point)
                                        ..end();
                                    },
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(
                                    widget.assets.file(widget.task.sample),
                                    fit: BoxFit.contain,
                                  ),
                                  if (_maskImage case final image?)
                                    CustomPaint(
                                      painter: _MaskPainter(image),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  editor?.lastInferenceMs == null
                      ? _hintFor(editor?.brush)
                      : '${editor!.lastInferenceMs!.toStringAsFixed(1)} ms  ·  '
                          '${editor.completedRequests} requests, '
                          '${editor.coalescedRequests} coalesced',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                SegmentedButton<SegmentationBrushMode>(
                  segments: const [
                    ButtonSegment(
                      value: SegmentationBrushMode.positive,
                      icon: Icon(Icons.add_circle_outline),
                      label: Text('Include'),
                    ),
                    ButtonSegment(
                      value: SegmentationBrushMode.negative,
                      icon: Icon(Icons.remove_circle_outline),
                      label: Text('Exclude'),
                    ),
                    ButtonSegment(
                      value: SegmentationBrushMode.lasso,
                      icon: Icon(Icons.gesture),
                      label: Text('Lasso'),
                    ),
                  ],
                  selected: {editor?.brush ?? SegmentationBrushMode.positive},
                  // The controller reads `brush` when a stroke begins, so a
                  // change mid-stroke cannot alter the stroke already running.
                  onSelectionChanged: editor == null || !editor.ready
                      ? null
                      : (selection) =>
                            setState(() => editor.brush = selection.first),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Threshold'),
                    Expanded(
                      child: Slider(
                        value: _threshold,
                        min: 0.05,
                        max: 0.95,
                        onChanged: (value) {
                          setState(() => _threshold = value);
                          unawaited(_repaintMask());
                        },
                      ),
                    ),
                    Text(_threshold.toStringAsFixed(2)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MaskPainter extends CustomPainter {
  const _MaskPainter(this.mask);

  final ui.Image mask;

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(
      canvas: canvas,
      rect: Offset.zero & size,
      image: mask,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_MaskPainter oldDelegate) => oldDelegate.mask != mask;
}
