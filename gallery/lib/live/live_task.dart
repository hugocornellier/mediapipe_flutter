import 'dart:typed_data';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

import 'task_settings.dart';

/// The task-specific half of a live demo: how to build it, and how to run one
/// frame through it. Everything else about live capture is identical between
/// tasks and lives in [LiveCameraController].
abstract interface class LiveTask<T> {
  /// Human-readable name, used in errors.
  String get name;

  /// The values [open] builds the task with; the page edits them and reopens.
  TaskSettingValues get settings;

  /// Creates the underlying VIDEO-mode task.
  Future<void> open(VisionDelegate delegate, Uint8List modelBytes);

  /// Runs one frame. Called at most once at a time.
  ///
  /// [rotationDegrees] is the clockwise rotation that stands the frame upright;
  /// MediaPipe applies it and still reports coordinates in the frame's own
  /// space, which is what [PreviewTransform] expects.
  Future<T> detect(
    VisionImage frame,
    int timestampMilliseconds, {
    required int rotationDegrees,
  });

  /// Releases native resources. Safe to call when never opened.
  Future<void> close();
}

/// Optional transport for decoded browser frames.
abstract interface class BrowserLiveTask<T> implements LiveTask<T> {
  Future<T> detectBrowserFrame(
    Object frame,
    int width,
    int height,
    int timestamp,
  );
}
