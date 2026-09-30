import 'dart:typed_data';
import 'package:mediapipe_vision/mediapipe_vision.dart';

import 'task_settings.dart';

/// The task-specific half of a live demo: how to build it, and how to run one
/// frame through it. Everything else about live capture is identical between
/// tasks and lives in [LiveCameraController].
abstract interface class LiveTask<T> {
  /// Human-readable name, used in errors.
  String get name;

  /// The values [open] builds the task with; the page edits them and reopens.
  TaskSettingValues get settings;

  /// Creates the task in the requested running mode.
  Future<void> open(
    VisionDelegate delegate,
    Uint8List modelBytes, {
    RunningMode mode = RunningMode.video,
  });

  /// Processes a still image with a task opened in image mode.
  Future<T> detectImage(VisionImage image);

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

/// A task that learns from the frames it sees, such as a reference that later
/// frames are compared with. The controller warms each task up on a sample
/// before the camera starts, then calls [forgetFrames] so the camera's first
/// frame finds the task as freshly opened.
abstract interface class StatefulLiveTask {
  void forgetFrames();
}

/// VIDEO tasks whose temporal state requires every frame to have the same
/// dimensions. A differently sized sample must not seed their state.
abstract interface class FixedFrameSizeLiveTask {}

/// Optional transport for decoded browser frames.
abstract interface class BrowserLiveTask<T> implements LiveTask<T> {
  Future<T> detectBrowserFrame(
    Object frame,
    int width,
    int height,
    int timestamp,
  );
}

/// Optional worker-rendered browser overlay. The regular Flutter painter stays
/// available when the browser cannot transfer a canvas or drawing fails.
abstract interface class BrowserOverlayLiveTask {
  Future<void> attachOverlay(Object canvas);
  void setOverlayOptions({
    required bool connections,
    required bool points,
    required bool mirrored,
    required double scale,
  });
  bool get overlayActive;
}
