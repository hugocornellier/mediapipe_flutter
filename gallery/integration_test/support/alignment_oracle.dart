import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_gallery/live/camera_geometry.dart';
import 'package:mediapipe_gallery/live/face_overlay.dart';
import 'package:mediapipe_gallery/live/live_camera_controller.dart';
import 'package:mediapipe_gallery/live/live_camera_view.dart';

/// Checks that the overlay lands on the face the viewer can actually see.
///
/// The geometry unit tests prove [PreviewTransform] is consistent with the
/// rules in `camera_geometry.dart`. They cannot prove those rules match what a
/// platform's camera plugin really does to its preview, which is the only
/// thing that decides whether the dots sit on the face. This oracle closes
/// that gap without a person: it screenshots the preview with the overlay
/// hidden, runs the same official IMAGE-mode task over those on-screen pixels,
/// and compares the face it finds there with where the overlay would draw the
/// live result. A wrong mirror puts the two on opposite sides of the box, a
/// wrong rotation puts them a quarter turn apart, and a wrong crop drifts them
/// toward an edge; all three fail the tolerance by an order of magnitude.

/// Nose tip, chin, forehead, iris centres, mouth corners, outer eye corners.
const alignmentProbes = <int>[1, 152, 10, 468, 473, 61, 291, 33, 263];

/// Accept this much disagreement, as a fraction of the preview diagonal.
///
/// VIDEO tracking versus a fresh IMAGE pass over rescaled screen pixels
/// differs by a few tenths of a percent on the fixture; the failure modes the
/// oracle exists for are tens of percent.
const alignmentTolerance = 0.015;

/// Decoded RGBA pixels.
typedef RgbaImage = ({Uint8List rgba, int width, int height});

/// Where the live view drew its overlay, in logical pixels, and the transform
/// it used to get there. Read from the live widget tree rather than
/// recomputed, so the test measures the real painter's geometry.
typedef OverlayGeometry = ({Rect box, PreviewTransform transform});

/// The face overlay's box and transform as currently laid out.
OverlayGeometry overlayGeometry(
  WidgetTester tester,
  LiveCameraController<Object?> controller,
) {
  final paint = find.descendant(
    of: find.byType(LiveCameraView),
    matching: find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is FaceOverlay,
    ),
  );
  expect(paint, findsOneWidget, reason: 'the face overlay must be painting');
  final box = tester.renderObject<RenderBox>(paint);
  final overlay = tester.widget<CustomPaint>(paint).painter! as FaceOverlay;
  return (
    box: box.localToGlobal(Offset.zero) & box.size,
    transform: overlay.transform,
  );
}

/// One comparison between the live overlay and the on-screen face.
final class AlignmentMeasurement {
  const AlignmentMeasurement({
    required this.observedFaces,
    required this.distances,
    required this.distancesIfMirrored,
    required this.cropSize,
  });

  /// Faces the IMAGE task found in the preview crop; the oracle needs one.
  final int observedFaces;

  /// Probe index to distance between overlay and on-screen landmark, as a
  /// fraction of the crop diagonal.
  final Map<int, double> distances;

  /// The same distances if the overlay had been mirrored the other way, so a
  /// failure report says which hypothesis the screen actually matches.
  final Map<int, double> distancesIfMirrored;

  /// Crop size in screenshot pixels.
  final Size cropSize;

  double get median => _median(distances.values);
  double get maximum => distances.values.fold(0.0, (a, b) => math.max(a, b));
  double get medianIfMirrored => _median(distancesIfMirrored.values);

  bool get aligned => observedFaces == 1 && maximum <= alignmentTolerance;

  Map<String, Object?> toJson() => {
    'observed_faces': observedFaces,
    'crop_size': [cropSize.width, cropSize.height],
    'tolerance': alignmentTolerance,
    'median': median,
    'maximum': maximum,
    'median_if_mirrored': medianIfMirrored,
    'aligned': aligned,
    'distances': {
      for (final entry in distances.entries) '${entry.key}': entry.value,
    },
  };

  static double _median(Iterable<double> values) {
    final sorted = values.toList()..sort();
    if (sorted.isEmpty) return double.nan;
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }
}

/// Decodes a PNG (or any codec Flutter supports) into raw RGBA.
Future<RgbaImage> decodeImage(Uint8List encoded) async {
  final codec = await ui.instantiateImageCodec(encoded);
  final image = (await codec.getNextFrame()).image;
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return (
      rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      width: image.width,
      height: image.height,
    );
  } finally {
    image.dispose();
    codec.dispose();
  }
}

/// Copies [region] out of [source]. The region is clamped to the image.
RgbaImage cropImage(RgbaImage source, Rect region) {
  final left = region.left.round().clamp(0, source.width);
  final top = region.top.round().clamp(0, source.height);
  final right = region.right.round().clamp(left, source.width);
  final bottom = region.bottom.round().clamp(top, source.height);
  final width = right - left, height = bottom - top;
  final out = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    final from = ((top + y) * source.width + left) * 4;
    out.setRange(y * width * 4, (y + 1) * width * 4, source.rgba, from);
  }
  return (rgba: out, width: width, height: height);
}

/// Bounding box of pixels close to [color], or null when none match.
Rect? boundsOfColor(RgbaImage image, Color color, {int slack = 8}) {
  var minX = image.width, minY = image.height, maxX = -1, maxY = -1;
  final r = (color.r * 255).round(),
      g = (color.g * 255).round(),
      b = (color.b * 255).round();
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final i = (y * image.width + x) * 4;
      if ((image.rgba[i] - r).abs() <= slack &&
          (image.rgba[i + 1] - g).abs() <= slack &&
          (image.rgba[i + 2] - b).abs() <= slack) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) return null;
  return Rect.fromLTRB(
    minX.toDouble(),
    minY.toDouble(),
    maxX + 1.0,
    maxY + 1.0,
  );
}

/// Runs the official IMAGE task over the preview's screen pixels and compares
/// the face it finds with where the overlay draws [liveFace].
///
/// [previewInScreenshot] is the overlay box in screenshot pixels and
/// [pixelsPerLogical] converts the overlay's logical coordinates to it.
Future<AlignmentMeasurement> measureAlignment({
  required RgbaImage screenshot,
  required Rect previewInScreenshot,
  required double pixelsPerLogical,
  required List<FaceLandmark> liveFace,
  required PreviewTransform transform,
  required Uint8List modelBytes,
}) async {
  final crop = cropImage(screenshot, previewInScreenshot);
  final task = await FaceLandmarker.create(
    FaceLandmarkerOptions(modelBytes: modelBytes, numFaces: 1),
  );
  final FaceLandmarkerResult found;
  try {
    found = await task.detectImage(
      VisionImage.fromPixels(
        pixels: crop.rgba,
        width: crop.width,
        height: crop.height,
        format: VisionPixelFormat.rgba,
      ),
    );
  } finally {
    await task.dispose();
  }
  final size = Size(crop.width.toDouble(), crop.height.toDouble());
  if (found.faceLandmarks.isEmpty) {
    return AlignmentMeasurement(
      observedFaces: 0,
      distances: const {},
      distancesIfMirrored: const {},
      cropSize: size,
    );
  }
  final observed = found.faceLandmarks.first;
  final diagonal = math.sqrt(
    size.width * size.width + size.height * size.height,
  );
  final mirrored = PreviewTransform(
    quarterTurns: transform.quarterTurns,
    mirror: !transform.mirror,
    uprightSize: transform.uprightSize,
    scale: transform.scale,
    offsetX: transform.offsetX,
    offsetY: transform.offsetY,
  );
  double distance(PreviewTransform hypothesis, int index) {
    final expected =
        hypothesis.map(liveFace[index].x, liveFace[index].y) * pixelsPerLogical;
    final seen = Offset(
      observed[index].x * size.width,
      observed[index].y * size.height,
    );
    return (expected - seen).distance / diagonal;
  }

  return AlignmentMeasurement(
    observedFaces: found.faceLandmarks.length,
    distances: {for (final i in alignmentProbes) i: distance(transform, i)},
    distancesIfMirrored: {
      for (final i in alignmentProbes) i: distance(mirrored, i),
    },
    cropSize: size,
  );
}
