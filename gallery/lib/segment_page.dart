import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';

import 'catalog.dart';
import 'gallery_theme.dart';
import 'live/task_settings.dart';
import 'live/task_settings_panel.dart';
import 'main.dart';
import 'segment/editor_controller.dart';
import 'segment/mask_overlay.dart';
import 'ui/components.dart';
import 'ui/design.dart';
import 'ui/workspace.dart';
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
  });

  final GalleryTask task;
  final GalleryAssets assets;
  final TaskPlatform platform;
  final VoidCallback? onOpenMenu;

  @override
  State<SegmentPage> createState() => _SegmentPageState();
}

class _SegmentPageState extends State<SegmentPage> {
  EditorController? _editor;
  InteractiveSegmenter? _task;
  ui.Image? _maskImage;
  String? _error;
  late final _values = TaskSettingValues(widget.task.runtimeId);
  late final List<TaskSetting> _settings =
      taskSettings[widget.task.runtimeId] ?? const [];

  /// Bumped on every rebuild, so the settings sheet redraws with the page.
  final _revision = ValueNotifier<int>(0);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _revision.value++;
  }

  /// Kept off the ends, where a mask would be all or nothing.
  double get _threshold => _values.share('threshold').clamp(0.05, 0.95);

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
    _revision.dispose();
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

  Widget _panel() => TaskSettingsPanel(
    settings: _settings,
    values: _values,
    delegates: _delegates,
    delegate: _delegate,
    // Until the open task is ready, so a switch never overlaps an open
    // still in flight.
    enabled: _editor?.ready ?? false,
    onChanged: (key, value) {
      setState(() => _values[key] = value);
      unawaited(_repaintMask());
    },
    onDelegate: (delegate) => unawaited(_setDelegate(delegate)),
    models: const [],
    model: null,
    uploaded: null,
    modelStatus: null,
    onModel: (_) {},
    onUpload: null,
    bundledModel: widget.task.model,
  );

  @override
  Widget build(BuildContext context) {
    final c = GalleryColors.of(context);
    final phone = MediaQuery.sizeOf(context).width < Sizes.compact;
    final editor = _editor;
    final error = _error ?? editor?.error;
    return TaskWorkspace(
      title: widget.task.title,
      onOpenMenu: widget.onOpenMenu,
      // Rebuilt with the page, so the sheet shows the current values.
      settings: ListenableBuilder(
        listenable: _revision,
        builder: (context, _) => _panel(),
      ),
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
        FeedFrame(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (error != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      error,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFF0F3F2)),
                    ),
                  ),
                )
              else if (editor == null || !editor.ready || _imageAspect == null)
                const Center(child: CircularProgressIndicator())
              else
                Center(
                  child: AspectRatio(
                    aspectRatio: _imageAspect!,
                    child: LayoutBuilder(
                      builder: (context, constraints) => Semantics(
                        label: 'Segmentation image',
                        identifier: 'segment-canvas-${_delegate.name}',
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
                              Image(
                                image: widget.assets.imageProvider(
                                  widget.task.sample,
                                ),
                                fit: BoxFit.contain,
                              ),
                              if (_maskImage case final image?)
                                CustomPaint(painter: _MaskPainter(image)),
                              // The stroke being drawn, as Google's sample
                              // shows it until the pointer lifts.
                              CustomPaint(
                                painter: _StrokePainter(editor.activePoints),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 14,
                bottom: 14,
                child: Row(
                  children: [
                    FeedButton(
                      icon: LucideIcons.undo2,
                      tooltip: 'Undo stroke',
                      onPressed: editor?.canUndo ?? false
                          ? () => editor!.undo()
                          : null,
                    ),
                    const SizedBox(width: 7),
                    FeedButton(
                      icon: LucideIcons.eraser,
                      tooltip: 'Clear selection',
                      // clear() reloads the image, which drops every stroke
                      // and the mask.
                      onPressed:
                          editor != null && editor.ready && editor.canUndo
                          ? () => unawaited(editor.clear())
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        FeedStatus(
          parts: [
            if (editor?.lastInferenceMs case final ms?) ...[
              '${ms.toStringAsFixed(1)} ms',
              '${editor!.completedRequests} requests',
              '${editor.coalescedRequests} coalesced',
            ] else
              _hintFor(editor?.brush),
          ],
          delegate: _delegate == VisionDelegate.gpu ? 'GPU' : 'CPU',
        ),
        // TODO: finish Exclude (negative) and Lasso strokes on every
        // platform, then restore the Include/Exclude/Lasso selector (a
        // Segmented<SegmentationBrushMode> setting editor.brush). Until then
        // the gallery offers Include only.
        const SizedBox(height: 11),
        OutputCard(
          title: 'Selection',
          count: editor?.canUndo ?? false ? 'Include' : null,
          empty: _hintFor(editor?.brush),
          child: editor?.mask == null
              ? null
              : Text(
                  'Pixels above ${_threshold.toStringAsFixed(2)} confidence '
                  'are drawn as the selection.',
                  style: TextStyle(color: c.muted, fontSize: Sizes.sm),
                ),
        ),
      ],
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
