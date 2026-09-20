import 'package:flutter/material.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

import 'camera_geometry.dart';
import 'face_overlay.dart';
import 'landmark_overlay.dart';
import 'live_camera_controller.dart';
import 'live_tasks.dart';
import 'live_registry_additions_web.dart'
    if (dart.library.io) 'live_registry_additions_native.dart';

/// The two things a live tile contributes beyond the shared controller.
///
/// The painter is handed the [PreviewTransform] rather than computing its own,
/// so no demo can disagree with the preview about where a landmark belongs.
typedef LiveDemo = ({
  LiveTask<Object?> Function() task,
  CustomPainter Function(
    Object? result,
    PreviewTransform transform,
    bool edges,
    bool points,
  )
  overlay,
});

/// Keyed by catalog tile id.
final _demos = <String, LiveDemo>{
  'face_landmarker_live': (
    task: FaceLandmarkerLiveTask.new,
    overlay: _faceOverlay,
  ),
  ...additionalLiveDemos(_landmarkOverlay),
};

LiveDemo? liveDemoFor(String id) => _demos[id];

// Face landmarks have their own painter: 478 points with connections, contours and
// irises, rather than one skeleton of official edges.
CustomPainter _faceOverlay(
  Object? result,
  PreviewTransform transform,
  bool edges,
  bool points,
) => FaceOverlay(
  result as FaceLandmarkerResult?,
  transform: transform,
  showConnections: edges,
  showPoints: points,
);

CustomPainter _landmarkOverlay(
  Object? result,
  PreviewTransform transform,
  bool edges,
  bool points,
) => LandmarkOverlay(
  figuresFor(result),
  transform: transform,
  showEdges: edges,
  showPoints: points,
);
