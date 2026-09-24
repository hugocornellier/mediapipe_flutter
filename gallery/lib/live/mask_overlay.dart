import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

import 'camera_geometry.dart';

/// Paints an Image Segmenter category mask as tinted cells over every block of
/// pixels that is not background, and lists the classes it covers. Background
/// is class 0, except in a single-class model such as the selfie segmenter,
/// whose one class is 0 and whose background is 255.
///
/// Google's segmenter answers a rotated frame with the upright mask resized to
/// the frame's dimensions (upstream-issues.md UP-017), so cells are placed in
/// the upright frame rather than turned as landmarks are.
class MaskOverlay extends CustomPainter {
  const MaskOverlay(this.mask, this.labels, {required this.transform});

  final CategoryMask mask;
  final List<String> labels;
  final PreviewTransform transform;

  /// Cells across the mask's longer side.
  static const _cells = 96;
  static const _color = Color(0xFFFFB454);

  @override
  void paint(Canvas canvas, Size size) {
    final step = math.max(1, math.max(mask.width, mask.height) ~/ _cells);
    final fill = Paint()..color = _color.withValues(alpha: 0.45);
    final background = labels.length == 1 ? 255 : 0;
    final cells = <int, int>{};
    var total = 0;
    for (var y = 0; y < mask.height; y += step) {
      final bottom = math.min(y + step, mask.height) / mask.height;
      int? start;
      for (var x = 0; x <= mask.width; x += step) {
        final value = x < mask.width
            ? mask.categories[y * mask.width + x]
            : background;
        if (x < mask.width) {
          total++;
          if (value != background) cells[value] = (cells[value] ?? 0) + 1;
        }
        // One rectangle per run of covered cells in this row.
        if (value != background) {
          start ??= x;
        } else if (start != null) {
          canvas.drawRect(
            Rect.fromPoints(
              transform.mapUpright(start / mask.width, y / mask.height),
              transform.mapUpright(
                math.min(x, mask.width) / mask.width,
                bottom,
              ),
            ),
            fill,
          );
          start = null;
        }
      }
    }
    final covered = cells.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final (i, MapEntry(key: value, value: count)) in covered.indexed) {
      final name = value < labels.length ? labels[value] : 'class $value';
      _text(canvas, '$name ${(100 * count / total).round()}%', i);
    }
  }

  void _text(Canvas canvas, String text, int line) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: _color,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          shadows: [Shadow(blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(12, 12 + line * 22.0));
  }

  @override
  bool shouldRepaint(MaskOverlay oldDelegate) =>
      oldDelegate.mask != mask || oldDelegate.transform != transform;
}

/// The mask overlay for a live Image Segmenter result, or null otherwise.
MaskOverlay? maskOverlayFor(Object? result, PreviewTransform transform) =>
    switch (result) {
      SegmentationResult(:final categoryMask?, :final labels) => MaskOverlay(
        categoryMask,
        labels,
        transform: transform,
      ),
      _ => null,
    };
