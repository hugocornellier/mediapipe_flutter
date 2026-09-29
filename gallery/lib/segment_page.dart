import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

import 'catalog.dart';
import 'gallery_content_surface.dart';
import 'gallery_task_header.dart';
import 'gallery_theme.dart';
import 'main.dart';
import 'segment/editor_controller.dart';
import 'segment/mask_overlay.dart';
import 'web/test_hooks.dart';

/// MagicTouch segmentation: drag over a subject to select it.
///
/// The editor controller and mask thresholding are the segmenter example's,
/// copied unchanged. They already coalesce in-flight requests, keep the task's
/// float mask intact, and serialise stroke edits against native work.
class SegmentPage extends StatefulWidget {
  const SegmentPage({
    super.key,
    required this.task,
    required this.assets,
    required this.platform,
    this.onOpenMenu,
    this.framed = false,
  });

  final GalleryTask task;
  final GalleryAssets assets;
  final TaskPlatform platform;
  final VoidCallback? onOpenMenu;
  final bool framed;

  @override
  State<SegmentPage> createState() => _SegmentPageState();
}

class _SegmentPageState extends State<SegmentPage> {
  EditorController? _editor;
  InteractiveSegmenter? _task;
  ui.Image? _maskImage;
  String? _error;
  double _threshold = 0.5;

  /// The sample's width over height. The tap area takes exactly this shape,
  /// so a tap's position is measured against the picture, not the letterbox.
  double? _imageAspect;
  int _paintedRevision = -1;
  int _openRevision = 0;

  late final List<VisionDelegate> _delegates =
      widget.task
          .capabilitiesFor(
            widget.platform,
            widget.assets.officialMacosLandmarkTasks,
          )
          .supportedDelegates
          .toList()
        ..sort((a, b) => a.index.compareTo(b.index));
  late VisionDelegate _delegate = preferredDelegate(_delegates);

  @override
  void initState() {
    super.initState();
    _resolveImageAspect();
    unawaited(_open());
  }

  void _resolveImageAspect() {
    final stream = widget.assets
        .imageProvider(widget.task.sample)
        .resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      stream.removeListener(listener);
      final aspect = info.image.width / info.image.height;
      info.dispose();
      if (mounted) setState(() => _imageAspect = aspect);
    });
    stream.addListener(listener);
  }

  Future<void> _open() async {
    final revision = ++_openRevision;
    try {
      final model = await rootBundle.load('assets/models/${widget.task.model}');
      final task = await InteractiveSegmenter.create(
        InteractiveSegmenterOptions(
          modelBytes: model.buffer.asUint8List(
            model.offsetInBytes,
            model.lengthInBytes,
          ),
          delegate: _delegate,
        ),
      );
      // A later open (a delegate switch) or leaving the page replaces this one.
      if (!mounted || revision != _openRevision) {
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
      if (mounted && revision == _openRevision) {
        setState(() => _error = '$error');
      }
    }
  }

  /// Reopens the segmenter on [delegate] with the same image; strokes and the
  /// mask start over, since they belong to the task being replaced.
  Future<void> _setDelegate(VisionDelegate delegate) async {
    if (delegate == _delegate) return;
    final editor = _editor;
    final task = _task;
    editor?.removeListener(_onEditorChanged);
    setState(() {
      _delegate = delegate;
      _editor = null;
      _task = null;
      _error = null;
      _maskImage?.dispose();
      _maskImage = null;
      _paintedRevision = -1;
    });
    await editor?.close();
    await task?.dispose();
    if (mounted) await _open();
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
    if (testHooks) _logMask(mask);
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

  /// For the browser tests (`?test-hooks`): the strokes sent and the mask's
  /// area, bounding box and centroid, normalized to the image, as one line.
  void _logMask(SegmentationMask mask) {
    final confidence = mask.confidence;
    var count = 0, minX = mask.width, minY = mask.height, maxX = -1, maxY = -1;
    var sumX = 0.0, sumY = 0.0;
    for (var y = 0; y < mask.height; y++) {
      for (var x = 0; x < mask.width; x++) {
        if (confidence[y * mask.width + x] < _threshold) continue;
        count++;
        sumX += x;
        sumY += y;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    String n(num value, int size) => (value / size).toStringAsFixed(2);
    final strokes = [
      for (final stroke in _editor?.strokes ?? const <SegmentationStroke>[])
        '${stroke.brushMode.name}@'
            '${stroke.points.map((p) => '${p.x.toStringAsFixed(2)},'
                '${p.y.toStringAsFixed(2)}').join(' ')}',
    ];
    debugPrint(
      'SEGMENT_MASK delegate=${_delegate.name} strokes=[${strokes.join('; ')}] '
      'size=${mask.width}x${mask.height} '
      'area=${(count / (mask.width * mask.height)).toStringAsFixed(3)} '
      '${count == 0 ? 'empty' : 'bbox=${n(minX, mask.width)},${n(minY, mask.height)}-'
                '${n(maxX, mask.width)},${n(maxY, mask.height)} '
                'centroid=${n(sumX / count, mask.width)},'
                '${n(sumY / count, mask.height)}'}',
    );
    // `?test-hooks=mask` also logs the exact strokes and the mask, one byte
    // per pixel, for comparison with Google's Python reference.
    if (Uri.base.queryParameters['test-hooks'] == 'mask') {
      final bytes = Uint8List(confidence.length);
      for (var i = 0; i < confidence.length; i++) {
        bytes[i] = (confidence[i] * 255).round().clamp(0, 255);
      }
      debugPrintSynchronously(
        'SEGMENT_MASK_DATA ${jsonEncode({
          'delegate': _delegate.name,
          'width': mask.width,
          'height': mask.height,
          'strokes': [
            for (final stroke in _editor?.strokes ?? const <SegmentationStroke>[]) {
                'brush': stroke.brushMode.name,
                'completed': stroke.isCompleted,
                'points': [
                  for (final p in stroke.points) [p.x, p.y],
                ],
              },
          ],
          'mask': base64Encode(bytes),
        })}',
      );
    }
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
    SegmentationBrushMode.lasso =>
      'Draw a shape around a subject to select it.',
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
      backgroundColor: widget.framed
          ? theme.colorScheme.surfaceContainerLow
          : null,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: widget.onOpenMenu == null
            ? null
            : IconButton(
                icon: const Icon(Icons.menu),
                tooltip: 'Open navigation',
                onPressed: widget.onOpenMenu,
              ),
        flexibleSpace: GalleryTaskHeader(taskTitle: widget.task.title),
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
      body: GalleryContentSurface(
        framed: widget.framed,
        child: Column(
          children: [
            Expanded(
              child: Container(
                color: GalleryTheme.preview,
                width: double.infinity,
                child: error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            error,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: GalleryTheme.white),
                          ),
                        ),
                      )
                    : editor == null || !editor.ready || _imageAspect == null
                    ? const Center(child: CircularProgressIndicator())
                    : Center(
                        child: AspectRatio(
                          aspectRatio: _imageAspect!,
                          child: LayoutBuilder(
                            builder: (context, constraints) => Semantics(
                              label: 'Segmentation image',
                              child: GestureDetector(
                                key: const ValueKey('segment-canvas'),
                                // On web a click on a tappable semantics node
                                // arrives as a positionless tap, which put every
                                // stroke at the image centre. Real pointer events
                                // carry where the user clicked.
                                excludeFromSemantics: true,
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
                                onTapUp:
                                    editor.brush == SegmentationBrushMode.lasso
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
                                    Image(
                                      image: widget.assets.imageProvider(
                                        widget.task.sample,
                                      ),
                                      fit: BoxFit.contain,
                                    ),
                                    if (_maskImage case final image?)
                                      CustomPaint(painter: _MaskPainter(image)),
                                    // The stroke being drawn, as Google's
                                    // sample shows it until the pointer lifts.
                                    CustomPaint(
                                      painter: _StrokePainter(
                                        editor.activePoints,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
                        : '${editor!.lastInferenceMs!.toStringAsFixed(1)} ms '
                              'on ${_delegate == VisionDelegate.gpu ? 'GPU' : 'CPU'}  ·  '
                              '${editor.completedRequests} requests, '
                              '${editor.coalescedRequests} coalesced',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  // TODO: finish Exclude (negative) and Lasso strokes on every
                  // platform, then restore the Include/Exclude/Lasso selector
                  // (a SegmentedButton<SegmentationBrushMode> setting
                  // editor.brush). Until then the gallery offers Include only.
                  if (_delegates.length > 1) ...[
                    const SizedBox(height: 8),
                    SegmentedButton<VisionDelegate>(
                      segments: [
                        for (final delegate in _delegates)
                          ButtonSegment(
                            value: delegate,
                            label: Text(
                              delegate == VisionDelegate.gpu ? 'GPU' : 'CPU',
                            ),
                          ),
                      ],
                      selected: {_delegate},
                      // Disabled until the open task is ready, so a switch
                      // never overlaps an open still in flight.
                      onSelectionChanged: editor == null || !editor.ready
                          ? null
                          : (selection) =>
                                unawaited(_setDelegate(selection.first)),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Threshold'),
                      Expanded(
                        // As in TaskSettingsPanel: Flutter 3.47's Slider keeps
                        // its value-bubble overlay entry shown, and on web an
                        // entry in the page's overlay is an empty page-sized
                        // semantics node above every control, so DOM hit tests
                        // land on it. The value is printed beside the slider.
                        child: Overlay.wrap(
                          alwaysSizeToContent: true,
                          child: Slider(
                            showValueIndicator: ShowValueIndicator.never,
                            value: _threshold,
                            min: 0.05,
                            max: 0.95,
                            onChanged: (value) {
                              setState(() => _threshold = value);
                              unawaited(_repaintMask());
                            },
                          ),
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
      ),
    );
  }
}

class _StrokePainter extends CustomPainter {
  const _StrokePainter(this.points);

  /// Normalized to the picture, which fills this painter exactly.
  final List<SegmentationPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = GalleryTheme.accentLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(points.first.x * size.width, points.first.y * size.height);
    for (final point in points.skip(1)) {
      path.lineTo(point.x * size.width, point.y * size.height);
    }
    if (points.length == 1) {
      canvas.drawCircle(
        Offset(points.first.x * size.width, points.first.y * size.height),
        3,
        paint..style = PaintingStyle.fill,
      );
    } else {
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_StrokePainter oldDelegate) =>
      oldDelegate.points.length != points.length;
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
