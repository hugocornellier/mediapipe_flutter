import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Each task's icon, keyed by runtime id, as the design draws them.
const taskIcons = <String, IconData>{
  'face_detector': LucideIcons.scanFace,
  'face_landmarker': LucideIcons.scanLine,
  'hand_landmarker': LucideIcons.hand,
  'gesture_recognizer': LucideIcons.fingerprint,
  'pose_landmarker': LucideIcons.activity,
  'holistic_landmarker': LucideIcons.userRound,
  'object_detector': LucideIcons.shapes,
  'image_classifier': LucideIcons.tags,
  'image_embedder': LucideIcons.brainCircuit,
  'image_segmenter': LucideIcons.layers3,
  'interactive_segmenter': LucideIcons.circleDot,
  'interactive_segmenter_legacy': LucideIcons.circleDot,
  'audio_classifier': LucideIcons.audioLines,
  'language_detector': LucideIcons.languages,
  'text_classifier': LucideIcons.speech,
  'text_embedder': LucideIcons.waves,
};

IconData taskIcon(String runtimeId) =>
    taskIcons[runtimeId] ?? LucideIcons.sparkles;

/// The design's order within each section; other tasks follow by title.
const _order = [
  'face_detector',
  'face_landmarker',
  'hand_landmarker',
  'gesture_recognizer',
  'pose_landmarker',
  'holistic_landmarker',
  'object_detector',
  'image_classifier',
  'image_embedder',
  'image_segmenter',
  'interactive_segmenter',
  'interactive_segmenter_legacy',
  'audio_classifier',
  'language_detector',
  'text_classifier',
  'text_embedder',
];

/// Sorts by the design's order, then by title.
int compareTasks(
  ({String runtimeId, String title}) a,
  ({String runtimeId, String title}) b,
) {
  int rank(String id) {
    final i = _order.indexOf(id);
    return i < 0 ? _order.length : i;
  }

  final byRank = rank(a.runtimeId).compareTo(rank(b.runtimeId));
  return byRank != 0 ? byRank : a.title.compareTo(b.title);
}
