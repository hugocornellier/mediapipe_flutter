import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

import 'camera_geometry.dart';

/// Landmarks the overlay-alignment oracles compare with the on-screen face:
/// nose tip, chin, forehead, iris centres, mouth corners, outer eye corners.
const faceAlignmentProbes = <int>[1, 152, 10, 468, 473, 61, 291, 33, 263];

/// Paints the facial landmarks and their connections over the preview.
///
/// Landmarks arrive normalized to the frame the camera delivered, which is not
/// what the preview shows on a phone, so [transform] does the rotating,
/// mirroring and fitting. No cropping or landmark smoothing.
class FaceOverlay extends CustomPainter {
  FaceOverlay(
    this.result, {
    required this.transform,
    required this.showConnections,
    required this.showPoints,
  });

  final FaceLandmarkerResult? result;
  final PreviewTransform transform;
  final bool showConnections;
  final bool showPoints;

  @override
  void paint(Canvas canvas, Size size) {
    final result = this.result;
    if (result == null) return;
    final connections = Paint()
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
      // One draw call per group: segment endpoints as x0, y0, x1, y1, ...
      void edges(List<(int, int)> connections, Paint paint) {
        final points = Float32List(connections.length * 4);
        var length = 0;
        for (final (start, end) in connections) {
          if (start >= positions.length || end >= positions.length) continue;
          points[length++] = positions[start].dx;
          points[length++] = positions[start].dy;
          points[length++] = positions[end].dx;
          points[length++] = positions[end].dy;
        }
        canvas.drawRawPoints(
          PointMode.lines,
          Float32List.sublistView(points, 0, length),
          paint,
        );
      }

      if (showConnections) {
        edges(FaceLandmarkConnections.tessellation, connections);
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
      oldDelegate.showConnections != showConnections ||
      oldDelegate.showPoints != showPoints;
}
