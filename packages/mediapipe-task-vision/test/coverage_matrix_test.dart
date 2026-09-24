import 'dart:convert';
import 'dart:io';

import 'package:mediapipe_flutter_vision/capabilities.dart';
import 'package:mediapipe_flutter_vision/face_landmarker_backend.dart';
import 'package:test/test.dart';

// The CI coverage gate (tool/coverage/gate.py) requires a passing row for
// every 'required' cell of tool/coverage/matrix.json. This keeps that matrix
// and the package's capability claims from drifting: a required cell must be
// a claimed capability, and an 'unsupported' cell must not be. Claims are
// read with every platform adapter registered and the official macOS and iOS
// runtimes selected, the configuration CI tests.
const _platforms = {
  'web': TaskPlatform(operatingSystem: 'web', architecture: 'unknown'),
  'android': TaskPlatform(operatingSystem: 'android', architecture: 'arm64'),
  'ios': TaskPlatform(
    operatingSystem: 'ios',
    architecture: 'arm64',
    version: '15.0',
  ),
  'macos': TaskPlatform(
    operatingSystem: 'macos',
    architecture: 'arm64',
    version: '14.0',
  ),
  'linux': TaskPlatform(operatingSystem: 'linux', architecture: 'x64'),
  'windows': TaskPlatform(operatingSystem: 'windows', architecture: 'x64'),
};

final _claims =
    <String, TaskCapabilities<VisionDelegate> Function(TaskPlatform)>{
      'face_detector': faceDetectorCapabilitiesForPlatform,
      'face_landmarker': faceLandmarkerCapabilitiesForPlatform,
      'gesture_recognizer': (p) => gestureRecognizerCapabilitiesForPlatform(
        p,
        officialMacosRuntime: true,
        officialIosRuntime: true,
      ),
      'hand_landmarker': (p) => handLandmarkerCapabilitiesForPlatform(
        p,
        officialMacosRuntime: true,
        officialIosRuntime: true,
      ),
      'holistic_landmarker': (p) => holisticLandmarkerCapabilitiesForPlatform(
        p,
        officialMacosRuntime: true,
        officialIosRuntime: true,
      ),
      'image_classifier': (p) => imageClassifierCapabilitiesForPlatform(
        p,
        officialMacosRuntime: true,
        officialIosRuntime: true,
      ),
      'image_embedder': (p) => imageEmbedderCapabilitiesForPlatform(
        p,
        officialMacosRuntime: true,
        officialIosRuntime: true,
      ),
      'image_segmenter': (p) => imageSegmenterCapabilitiesForPlatform(
        p,
        officialMacosRuntime: true,
        officialIosRuntime: true,
      ),
      'interactive_segmenter': (p) =>
          interactiveSegmenterCapabilitiesForPlatform(
            p,
            officialIosRuntime: true,
          ),
      'object_detector': (p) => objectDetectorCapabilitiesForPlatform(
        p,
        officialMacosRuntime: true,
        officialIosRuntime: true,
      ),
      'pose_landmarker': (p) => poseLandmarkerCapabilitiesForPlatform(
        p,
        officialMacosRuntime: true,
        officialIosRuntime: true,
      ),
    };

Never _unused(Object? _) => throw UnimplementedError();

void main() {
  setUpAll(() {
    faceLandmarkerBackendFactory = _unused;
    faceDetectorBackendFactory = _unused;
    handLandmarkerBackendFactory = _unused;
    poseLandmarkerBackendFactory = _unused;
    gestureRecognizerBackendFactory = _unused;
    holisticLandmarkerBackendFactory = _unused;
    objectDetectorBackendFactory = _unused;
    imageClassifierBackendFactory = _unused;
    imageEmbedderBackendFactory = _unused;
    imageSegmenterBackendFactory = _unused;
    interactiveSegmenterBackendFactory = _unused;
  });

  test('coverage matrix agrees with the vision capability claims', () {
    final matrix =
        jsonDecode(
              File('../../tool/coverage/matrix.json').readAsStringSync(),
            )['cells']
            as Map<String, Object?>;
    final problems = <String>[];
    for (final MapEntry(key: task, value: claim) in _claims.entries) {
      final platforms = matrix[task]! as Map<String, Object?>;
      for (final MapEntry(key: name, value: platform) in _platforms.entries) {
        final claimed = claim(platform).supportedDelegates;
        final cells = platforms[name]! as Map<String, Object?>;
        for (final delegate in VisionDelegate.values) {
          final status = cells[delegate.name]! as String;
          final cell = '$task / $name / ${delegate.name}';
          if (status == 'required' && !claimed.contains(delegate)) {
            problems.add('$cell is required but not claimed');
          }
          if (status.startsWith('unsupported') && claimed.contains(delegate)) {
            problems.add('$cell is claimed but marked "$status"');
          }
        }
      }
    }
    expect(problems, isEmpty);
  });
}
