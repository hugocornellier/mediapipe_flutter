import 'package:flutter/material.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

import 'camera_geometry.dart';

/// One set of landmarks and the official edges joining them.
typedef LandmarkFigure = ({
  List<VisionLandmark> landmarks,
  List<(int, int)> edges,
  Color color,
});

/// Paints any landmark task's output.
///
/// Landmarks are normalized to the frame the camera delivered, so [transform]
/// rotates, mirrors and fits them onto the preview. Edge lists come from
/// `landmark_connections.dart`, which is generated from the official API, so
/// nothing here encodes a topology of its own.
class LandmarkOverlay extends CustomPainter {
  const LandmarkOverlay(
    this.figures, {
    required this.transform,
    required this.showEdges,
    required this.showPoints,
  });

  final List<LandmarkFigure> figures;
  final PreviewTransform transform;
  final bool showEdges;
  final bool showPoints;

  @override
  void paint(Canvas canvas, Size size) {
    for (final figure in figures) {
      final points = figure.landmarks;
      if (points.isEmpty) continue;
      Offset at(int index) => transform.map(points[index].x, points[index].y);
      if (showEdges) {
        final stroke = Paint()
          ..color = figure.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        for (final (start, end) in figure.edges) {
          if (start >= points.length || end >= points.length) continue;
          canvas.drawLine(at(start), at(end), stroke);
        }
      }
      if (showPoints) {
        final dot = Paint()..color = figure.color;
        for (var i = 0; i < points.length; i++) {
          canvas.drawCircle(at(i), 2.5, dot);
        }
      }
    }
  }

  @override
  bool shouldRepaint(LandmarkOverlay oldDelegate) =>
      oldDelegate.figures != figures ||
      oldDelegate.transform != transform ||
      oldDelegate.showEdges != showEdges ||
      oldDelegate.showPoints != showPoints;
}

/// Figures for one result, or an empty list when nothing was detected.
List<LandmarkFigure> figuresFor(Object? result) => switch (result) {
  final HandLandmarkerResult hands => [
    for (var i = 0; i < hands.handLandmarks.length; i++)
      (
        landmarks: hands.handLandmarks[i],
        edges: HandLandmarkConnections.all,
        color: i == 0 ? const Color(0xFF63E6BE) : const Color(0xFFFFD166),
      ),
  ],
  final PoseLandmarkerResult poses => [
    for (final landmarks in poses.poseLandmarks)
      (
        landmarks: landmarks,
        edges: PoseLandmarkConnections.all,
        color: const Color(0xFF8AB4FF),
      ),
  ],
  _ => const [],
};
