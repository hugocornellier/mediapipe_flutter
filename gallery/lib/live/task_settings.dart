/// The settings a live demo exposes, as MediaPipe Studio shows them for the
/// same task. Each key is the option's name in the task's Dart options class,
/// and each default is the value the gallery used before settings existed.
sealed class TaskSetting {
  const TaskSetting(this.key, this.label);

  /// The options field this setting sets.
  final String key;

  /// The label Studio uses for it.
  final String label;

  Object get initial;
}

/// A whole number within [min] and [max], such as Num Faces.
final class CountSetting extends TaskSetting {
  const CountSetting(
    super.key,
    super.label, {
    required this.initial,
    this.min = 1,
    this.max = 10,
  });

  @override
  final int initial;
  final int min;
  final int max;
}

/// A value between 0 and 1, such as a confidence or a score threshold.
final class ShareSetting extends TaskSetting {
  const ShareSetting(super.key, super.label, {this.initial = 0.5});

  @override
  final double initial;
}

/// An on/off option, such as Output Segmentation Masks.
final class SwitchSetting extends TaskSetting {
  const SwitchSetting(super.key, super.label, {this.initial = false});

  @override
  final bool initial;
}

const _handSettings = [
  CountSetting('numHands', 'Num Hands', initial: 2, max: 4),
  ShareSetting('minHandDetectionConfidence', 'Min Hand Detection Confidence'),
  ShareSetting('minHandPresenceConfidence', 'Min Hand Presence Confidence'),
  ShareSetting('minTrackingConfidence', 'Min Tracking Confidence'),
];

/// Keyed by the catalog's runtime id.
const taskSettings = <String, List<TaskSetting>>{
  'face_detector': [
    ShareSetting('minDetectionConfidence', 'Min Detection Confidence'),
    ShareSetting(
      'minSuppressionThreshold',
      'Min Suppression Threshold',
      initial: 0.3,
    ),
  ],
  'face_landmarker': [
    CountSetting('numFaces', 'Num Faces', initial: 1),
    ShareSetting('minFaceDetectionConfidence', 'Min Detection Confidence'),
    ShareSetting('minFacePresenceConfidence', 'Min Presence Confidence'),
    ShareSetting('minTrackingConfidence', 'Min Tracking Confidence'),
  ],
  'hand_landmarker': _handSettings,
  'gesture_recognizer': [
    ..._handSettings,
    CountSetting('maxResults', 'Max Results', initial: 1, max: 8),
    ShareSetting('scoreThreshold', 'Score Threshold', initial: 0),
  ],
  'pose_landmarker': [
    CountSetting('numPoses', 'Num Poses', initial: 1, max: 5),
    ShareSetting('minPoseDetectionConfidence', 'Min Pose Detection Confidence'),
    ShareSetting('minPosePresenceConfidence', 'Min Pose Presence Confidence'),
    ShareSetting('minTrackingConfidence', 'Min Tracking Confidence'),
    SwitchSetting('outputSegmentationMasks', 'Output Segmentation Masks'),
  ],
  'holistic_landmarker': [
    ShareSetting('minFaceDetectionConfidence', 'Min Face Detection Confidence'),
    ShareSetting(
      'minFaceSuppressionThreshold',
      'Min Face Suppression Threshold',
    ),
    ShareSetting('minFacePresenceConfidence', 'Min Face Presence Confidence'),
    ShareSetting('minPoseDetectionConfidence', 'Min Pose Detection Confidence'),
    ShareSetting(
      'minPoseSuppressionThreshold',
      'Min Pose Suppression Threshold',
    ),
    ShareSetting('minPosePresenceConfidence', 'Min Pose Presence Confidence'),
    ShareSetting('minHandLandmarksConfidence', 'Min Hand Landmarks Confidence'),
    SwitchSetting('outputPoseSegmentationMask', 'Output Segmentation Mask'),
  ],
  'object_detector': [
    CountSetting('maxResults', 'Max Results', initial: 5, max: 25),
    ShareSetting('scoreThreshold', 'Score Threshold', initial: 0.3),
  ],
  'image_classifier': [
    CountSetting('maxResults', 'Max Results', initial: 3),
    ShareSetting('scoreThreshold', 'Score Threshold', initial: 0),
  ],
  'image_embedder': [
    SwitchSetting('l2Normalize', 'L2 Normalize'),
    SwitchSetting('quantize', 'Quantize'),
  ],
  'audio_classifier': [
    CountSetting('maxResults', 'Max Results', initial: 3),
    ShareSetting('scoreThreshold', 'Score Threshold', initial: 0),
  ],
  'text_classifier': [
    CountSetting('maxResults', 'Max Results', initial: 3),
    ShareSetting('scoreThreshold', 'Score Threshold', initial: 0),
  ],
  'language_detector': [
    CountSetting('maxResults', 'Max Results', initial: 3),
    ShareSetting('scoreThreshold', 'Score Threshold', initial: 0),
  ],
  'text_embedder': [
    SwitchSetting('l2Normalize', 'L2 Normalize'),
    SwitchSetting('quantize', 'Quantize'),
  ],
};

/// The current value of every setting of one task.
final class TaskSettingValues {
  TaskSettingValues(String task)
    : _values = {
        for (final setting in taskSettings[task] ?? const <TaskSetting>[])
          setting.key: setting.initial,
      };

  final Map<String, Object> _values;

  int count(String key) => _values[key]! as int;
  double share(String key) => _values[key]! as double;
  bool on(String key) => _values[key]! as bool;

  Object operator [](String key) => _values[key]!;
  void operator []=(String key, Object value) => _values[key] = value;
}
