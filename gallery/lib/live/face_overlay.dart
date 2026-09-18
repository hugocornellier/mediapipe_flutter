import 'package:flutter/material.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

import 'camera_geometry.dart';

/// Paints the face mesh over the preview.
///
/// Landmarks arrive normalized to the frame the camera delivered, which is not
/// what the preview shows on a phone, so [transform] does the rotating,
/// mirroring and fitting. No cropping or landmark smoothing.
class FaceOverlay extends CustomPainter {
  FaceOverlay(
    this.result, {
    required this.transform,
    required this.showMesh,
    required this.showPoints,
  });

  final FaceLandmarkerResult? result;
  final PreviewTransform transform;
  final bool showMesh;
  final bool showPoints;

  @override
  void paint(Canvas canvas, Size size) {
    final result = this.result;
    if (result == null) return;
    final mesh = Paint()
      ..color = const Color(0x7063e6be)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    final contour = Paint()
      ..color = const Color(0xff63e6be)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final iris = Paint()
      ..color = const Color(0xffffce73)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    final point = Paint()..color = Colors.white;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final face in result.faceLandmarks) {
      final positions = [
        for (final landmark in face) transform.map(landmark.x, landmark.y),
      ];
      void edges(List<(int, int)> connections, Paint paint) {
        final path = Path();
        for (final (start, end) in connections) {
          if (start >= positions.length || end >= positions.length) continue;
          path.moveTo(positions[start].dx, positions[start].dy);
          path.lineTo(positions[end].dx, positions[end].dy);
        }
        canvas.drawPath(path, paint);
      }

      if (showMesh) {
        edges(FaceLandmarkConnections.tessellation, mesh);
        edges(FaceLandmarkConnections.contours, contour);
        edges(FaceLandmarkConnections.leftIris, iris);
        edges(FaceLandmarkConnections.rightIris, iris);
      }
      if (showPoints) {
        for (final position in positions) {
          canvas.drawCircle(position, 1.4, point);
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(FaceOverlay oldDelegate) =>
      oldDelegate.result != result ||
      oldDelegate.transform != transform ||
      oldDelegate.showMesh != showMesh ||
      oldDelegate.showPoints != showPoints;
}
