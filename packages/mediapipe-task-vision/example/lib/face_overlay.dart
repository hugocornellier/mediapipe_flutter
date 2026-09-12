import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

/// The macOS plugin mirrors both the preview and streamed pixels natively.
/// Scale original input coordinates once; do not apply another mirror or crop.
class FaceOverlay extends CustomPainter {
  FaceOverlay(this.result, {required this.showKeypoints});

  final FaceDetectorResult? result;
  final bool showKeypoints;

  @override
  void paint(Canvas canvas, Size size) {
    final result = this.result;
    if (result == null) return;
    final sx = size.width / result.imageWidth;
    final sy = size.height / result.imageHeight;
    final boxPaint = Paint()
      ..color = const Color(0xff63e6be)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final pointPaint = Paint()..color = Colors.white;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final face in result.detections) {
      final box = face.boundingBox;
      canvas.drawRect(
        Rect.fromLTRB(
          box.left * sx,
          box.top * sy,
          box.right * sx,
          box.bottom * sy,
        ),
        boxPaint,
      );
      if (showKeypoints) {
        for (final point in face.keypoints) {
          canvas.drawCircle(
            Offset(point.x * size.width, point.y * size.height),
            3,
            pointPaint,
          );
        }
      }
      if (face.categories.isNotEmpty) {
        final label = TextPainter(
          text: TextSpan(
            text: '${(face.categories.first.score * 100).round()}%',
            style: const TextStyle(
              color: Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final origin = Offset(
          (box.left * sx).clamp(0, math.max(0, size.width - label.width - 10)),
          (box.top * sy - 25).clamp(0, math.max(0, size.height - 24)),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            origin & Size(label.width + 10, 22),
            const Radius.circular(4),
          ),
          Paint()..color = boxPaint.color,
        );
        label.paint(canvas, origin + const Offset(5, 3));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(FaceOverlay oldDelegate) =>
      oldDelegate.result != result ||
      oldDelegate.showKeypoints != showKeypoints;
}
