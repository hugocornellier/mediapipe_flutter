import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

import 'editor_controller.dart';
import 'editor_geometry.dart';
import 'mask_overlay.dart';

void main() => runApp(const SegmenterApp());

class SegmenterApp extends StatelessWidget {
  const SegmenterApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MagicTouch',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xff43eeb5),
      scaffoldBackgroundColor: const Color(0xff111815),
      useMaterial3: true,
    ),
    home: const SegmenterEditor(),
  );
}

class SegmenterEditor extends StatefulWidget {
  const SegmenterEditor({super.key});

  @override
  State<SegmenterEditor> createState() => _SegmenterEditorState();
}

class _SegmenterEditorState extends State<SegmenterEditor> {
  EditorController? _editor;
  ui.Image? _image;
  ui.Image? _overlay;
  SegmentationMask? _renderedMask;
  String _imageName = 'Animals';
  String? _error;
  bool _loading = true;
  bool _showOverlay = true;
  double _threshold = 0.5;
  double? _overlayMs;
  int _imageGeneration = 0;
  int _overlayGeneration = 0;
  int? _pointer;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final model = await rootBundle.load(
        'assets/interactive_segmentation.task',
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
      _editor = EditorController(NativeSegmentationBackend(task))
        ..addListener(_changed);
      await _sample('animals.jpg', 'Animals');
      if (mounted && _editor!.ready) {
        _editor!
          ..begin(SegmentationPoint(x: 0.66, y: 0.55))
          ..end();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _sample(String asset, String name) async {
    await _loadBytes(() async {
      final bytes = await rootBundle.load('assets/$asset');
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    }, name);
  }

  Future<void> _open() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Images',
            extensions: ['jpg', 'jpeg', 'png'],
            uniformTypeIdentifiers: ['public.jpeg', 'public.png'],
          ),
        ],
      );
      if (file != null && mounted) {
        await _loadBytes(file.readAsBytes, file.name);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _loadBytes(
    Future<Uint8List> Function() read,
    String name,
  ) async {
    final generation = ++_imageGeneration;
    _overlayGeneration++;
    _pointer = null;
    setState(() {
      _loading = true;
      _error = null;
    });
    ui.Image? decoded;
    try {
      final codec = await ui.instantiateImageCodec(await read());
      try {
        decoded = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
      // Both the canvas and MediaPipe use these exact oriented, unscaled pixels.
      final rgba = await decoded.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (!mounted || generation != _imageGeneration) return;
      if (rgba == null) throw StateError('Image has no readable pixels.');
      final image = VisionImage.fromPixels(
        pixels: rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
        width: decoded.width,
        height: decoded.height,
        format: VisionPixelFormat.rgba,
      );
      await _editor!.loadImage(image);
      if (!mounted || generation != _imageGeneration) return;
      final previous = _image;
      setState(() {
        _image = decoded;
        decoded = null;
        _imageName = name;
        _loading = false;
      });
      previous?.dispose();
    } catch (error) {
      if (mounted && generation == _imageGeneration) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    } finally {
      decoded?.dispose();
    }
  }

  void _changed() {
    if (!mounted) return;
    final mask = _editor!.mask;
    if (!identical(mask, _renderedMask)) {
      _renderedMask = mask;
      unawaited(_renderMask(mask));
    }
    setState(() {});
  }

  Future<void> _renderMask(SegmentationMask? mask) async {
    final generation = ++_overlayGeneration;
    if (mask == null) {
      final previous = _overlay;
      setState(() {
        _overlay = null;
        _overlayMs = null;
      });
      previous?.dispose();
      return;
    }
    final watch = Stopwatch()..start();
    try {
      final rgba = await _maskPixels(mask.confidence, _threshold);
      if (!mounted || generation != _overlayGeneration) return;
      final completed = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgba,
        mask.width,
        mask.height,
        ui.PixelFormat.rgba8888,
        completed.complete,
      );
      final overlay = await completed.future;
      if (!mounted || generation != _overlayGeneration) {
        overlay.dispose();
        return;
      }
      final previous = _overlay;
      setState(() {
        _overlay = overlay;
        _overlayMs = watch.elapsedMicroseconds / 1000;
      });
      previous?.dispose();
    } catch (error) {
      if (mounted && generation == _overlayGeneration) {
        setState(() => _error = error.toString());
      }
    }
  }

  @override
  void dispose() {
    _imageGeneration++;
    _overlayGeneration++;
    _editor?.removeListener(_changed);
    _editor?.dispose();
    _image?.dispose();
    _overlay?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editor = _editor;
    final canEdit = !_loading && editor != null && editor.ready;
    final error = _error ?? editor?.error;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 24,
                runSpacing: 12,
                children: [
                  const Text(
                    'MagicTouch',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
                  ),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Chip(label: Text('CPU · macOS')),
                      TextButton(
                        onPressed: _loading || editor == null
                            ? null
                            : () => _sample('animals.jpg', 'Animals'),
                        child: const Text('Animals'),
                      ),
                      TextButton(
                        onPressed: _loading || editor == null
                            ? null
                            : () => _sample('portrait.jpg', 'Portrait'),
                        child: const Text('Portrait'),
                      ),
                      FilledButton.icon(
                        onPressed: _loading || editor == null ? null : _open,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Open image'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<SegmentationBrushMode>(
                    segments: const [
                      ButtonSegment(
                        value: SegmentationBrushMode.positive,
                        icon: Icon(Icons.add),
                        label: Text('Include'),
                      ),
                      // TODO: Re-add the Exclude (negative) and Lasso brushes
                      // once they are better tested.
                    ],
                    selected: {editor?.brush ?? SegmentationBrushMode.positive},
                    onSelectionChanged: canEdit
                        ? (value) => setState(() => editor.brush = value.single)
                        : null,
                  ),
                  TextButton.icon(
                    onPressed: canEdit && editor.canUndo ? editor.undo : null,
                    icon: const Icon(Icons.undo),
                    label: const Text('Undo'),
                  ),
                  TextButton.icon(
                    onPressed: !_loading && editor != null && _image != null
                        ? editor.clear
                        : null,
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear'),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: _showOverlay,
                        onChanged: (value) =>
                            setState(() => _showOverlay = value!),
                      ),
                      const Text('Mask'),
                      SizedBox(
                        width: 140,
                        child: Slider(
                          value: _threshold,
                          min: 0.05,
                          max: 0.95,
                          divisions: 90,
                          label: _threshold.toStringAsFixed(2),
                          onChanged: (value) {
                            setState(() => _threshold = value);
                            unawaited(_renderMask(editor?.mask));
                          },
                        ),
                      ),
                      Text(_threshold.toStringAsFixed(2)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ColoredBox(
                    color: const Color(0xff080e0b),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_image case final image?)
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final rect = containedImageRect(
                                Size(
                                  image.width.toDouble(),
                                  image.height.toDouble(),
                                ),
                                constraints.biggest,
                              );
                              return MouseRegion(
                                cursor: canEdit
                                    ? SystemMouseCursors.precise
                                    : SystemMouseCursors.basic,
                                child: Listener(
                                  key: const Key('image-canvas'),
                                  behavior: HitTestBehavior.opaque,
                                  onPointerDown: (event) {
                                    if (!canEdit ||
                                        _pointer != null ||
                                        event.buttons != kPrimaryButton) {
                                      return;
                                    }
                                    final point = imagePoint(
                                      event.localPosition,
                                      rect,
                                    );
                                    if (point == null) return;
                                    _pointer = event.pointer;
                                    editor.begin(point);
                                  },
                                  onPointerMove: (event) {
                                    if (!canEdit || event.pointer != _pointer) {
                                      return;
                                    }
                                    final point = imagePoint(
                                      event.localPosition,
                                      rect,
                                    );
                                    if (point != null) editor.extend(point);
                                  },
                                  onPointerUp: (event) {
                                    if (event.pointer != _pointer) return;
                                    _pointer = null;
                                    editor?.end();
                                  },
                                  onPointerCancel: (event) {
                                    if (event.pointer != _pointer) return;
                                    _pointer = null;
                                    editor?.end();
                                  },
                                  child: CustomPaint(
                                    painter: _SelectionPainter(
                                      image: image,
                                      overlay: _showOverlay ? _overlay : null,
                                      rect: rect,
                                      strokes: editor?.strokes ?? [],
                                      activePoints: editor?.activePoints ?? [],
                                      activeBrush:
                                          editor?.activeBrush ??
                                          SegmentationBrushMode.positive,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        if (_loading)
                          const Center(child: CircularProgressIndicator()),
                        if (editor?.busy ?? false)
                          const Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text(
                    _image == null
                        ? 'Loading official MagicTouch model…'
                        : '$_imageName · ${_image!.width} × ${_image!.height}',
                  ),
                  Text(
                    editor?.lastInferenceMs == null
                        ? 'Click an object or draw a stroke to select it.'
                        : '${editor!.lastInferenceMs!.toStringAsFixed(1)} ms inference'
                              ' · ${(_overlayMs ?? 0).toStringAsFixed(1)} ms overlay',
                  ),
                ],
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SelectableText(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// A top-level helper prevents Isolate.run from capturing UI/native resources.
Future<Uint8List> _maskPixels(Float32List confidence, double threshold) =>
    Isolate.run(() => maskRgba(confidence, threshold));

class _SelectionPainter extends CustomPainter {
  _SelectionPainter({
    required this.image,
    required this.overlay,
    required this.rect,
    required this.strokes,
    required this.activePoints,
    required this.activeBrush,
  });
  final ui.Image image;
  final ui.Image? overlay;
  final Rect rect;
  final List<SegmentationStroke> strokes;
  final List<SegmentationPoint> activePoints;
  final SegmentationBrushMode activeBrush;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.medium,
    );
    if (overlay case final mask?) {
      canvas.drawImageRect(
        mask,
        Rect.fromLTWH(0, 0, mask.width.toDouble(), mask.height.toDouble()),
        rect,
        Paint()..filterQuality = FilterQuality.low,
      );
    }
    canvas.save();
    canvas.clipRect(rect);
    for (final stroke in strokes) {
      _stroke(canvas, stroke.points, stroke.brushMode);
    }
    if (activeBrush == SegmentationBrushMode.lasso && activePoints.length < 3) {
      _stroke(canvas, activePoints, activeBrush);
    }
    canvas.restore();
  }

  void _stroke(
    Canvas canvas,
    List<SegmentationPoint> points,
    SegmentationBrushMode mode,
  ) {
    if (points.isEmpty) return;
    final color = switch (mode) {
      SegmentationBrushMode.positive => const Color(0xff43eeb5),
      SegmentationBrushMode.negative => const Color(0xffff7b7b),
      SegmentationBrushMode.lasso => const Color(0xffc5a3ff),
    };
    Offset offset(SegmentationPoint p) =>
        Offset(rect.left + p.x * rect.width, rect.top + p.y * rect.height);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final start = offset(points.first);
    if (points.length == 1) {
      canvas.drawCircle(start, 5, Paint()..color = Colors.black54);
      canvas.drawCircle(start, 4, paint);
    } else {
      final path = Path()..moveTo(start.dx, start.dy);
      for (final point in points.skip(1)) {
        final position = offset(point);
        path.lineTo(position.dx, position.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SelectionPainter oldDelegate) => true;
}
