import 'package:flutter/material.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

import 'face_overlay.dart';
import 'landmark_overlay.dart';
import 'live_camera_controller.dart';
import 'live_tasks.dart';

/// The two things a live tile contributes beyond the shared controller.
typedef LiveDemo = ({
  LiveTask<Object?> Function() task,
  CustomPainter Function(Object? result, bool edges, bool points) overlay,
});

/// Keyed by catalog tile id.
const _demos = <String, LiveDemo>{
  'face_landmarker_live': (
    task: FaceLandmarkerLiveTask.new,
    overlay: _faceOverlay,
  ),
  'hand_landmarker_live': (
    task: HandLandmarkerLiveTask.new,
    overlay: _landmarkOverlay,
  ),
  'pose_landmarker_live': (
    task: PoseLandmarkerLiveTask.new,
    overlay: _landmarkOverlay,
  ),
};

LiveDemo? liveDemoFor(String id) => _demos[id];

// The face mesh has its own painter: 478 points with tessellation, contours and
// irises, rather than one skeleton of official edges.
CustomPainter _faceOverlay(Object? result, bool edges, bool points) =>
    FaceOverlay(
      result as FaceLandmarkerResult?,
      showMesh: edges,
      showPoints: points,
    );

CustomPainter _landmarkOverlay(Object? result, bool edges, bool points) =>
    LandmarkOverlay(
      figuresFor(result),
      showEdges: edges,
      showPoints: points,
    );
