import 'package:flutter/painting.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

Rect containedImageRect(Size image, Size viewport) {
  final fitted = applyBoxFit(BoxFit.contain, image, viewport);
  return Alignment.center.inscribe(fitted.destination, Offset.zero & viewport);
}

SegmentationPoint? imagePoint(Offset position, Rect rect) {
  if (rect.isEmpty ||
      position.dx < rect.left ||
      position.dx > rect.right ||
      position.dy < rect.top ||
      position.dy > rect.bottom) {
    return null;
  }
  return SegmentationPoint(
    x: ((position.dx - rect.left) / rect.width).clamp(0, 1),
    y: ((position.dy - rect.top) / rect.height).clamp(0, 1),
  );
}
