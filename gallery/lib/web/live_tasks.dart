import 'dart:typed_data';

import 'package:mediapipe_vision/mediapipe_vision.dart';

import '../live/live_task.dart';
import '../live/task_settings.dart';

/// Browser transport shared by every public task on the official web adapter:
/// each demo supplies only its name and how its task is built.
abstract base class _WebLiveTask<R>
    implements BrowserLiveTask<R>, BrowserOverlayLiveTask {
  BrowserVisionTask<R>? _task;

  /// Creates a task in the requested running mode.
  Future<Object> create(
    VisionDelegate delegate,
    Uint8List model,
    RunningMode mode,
  );

  @override
  Future<void> open(
    VisionDelegate delegate,
    Uint8List modelBytes, {
    RunningMode mode = RunningMode.video,
  }) async {
    // The primary package export selects the browser implementations on web.
    _task = await create(delegate, modelBytes, mode) as BrowserVisionTask<R>;
  }

  @override
  Future<R> detectImage(VisionImage image) => _task!.detectImage(image);

  @override
  Future<R> detect(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.detectForVideo(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  Future<R> detectBrowserFrame(
    Object frame,
    int width,
    int height,
    int timestamp,
  ) => _task!.detectBrowserFrame(
    frame,
    width: width,
    height: height,
    timestampMilliseconds: timestamp,
  );

  @override
  Future<void> attachOverlay(Object canvas) =>
      _task!.attachBrowserOverlay(canvas);

  @override
  void setOverlayOptions({
    required bool connections,
    required bool points,
    required bool mirrored,
    required double scale,
  }) => _task?.setBrowserOverlayOptions(
    connections: connections,
    points: points,
    mirrored: mirrored,
    scale: scale,
  );

  @override
  bool get overlayActive => _task?.browserOverlayActive ?? false;

  @override
  Future<void> close() async {
    final task = _task;
    _task = null;
    await task?.dispose();
  }
}

/// Browser transport for the same public FaceLandmarker task.
final class FaceLandmarkerLiveTask extends _WebLiveTask<FaceLandmarkerResult> {
  @override
  final settings = TaskSettingValues('face_landmarker');

  @override
  String get name => 'Face Landmarker';

  @override
  Future<FaceLandmarker> create(
    VisionDelegate delegate,
    Uint8List model,
    RunningMode mode,
  ) => FaceLandmarker.create(
    FaceLandmarkerOptions(
      modelBytes: model,
      runningMode: mode,
      delegate: delegate,
      numFaces: settings.count('numFaces'),
      minFaceDetectionConfidence: settings.share('minFaceDetectionConfidence'),
      minFacePresenceConfidence: settings.share('minFacePresenceConfidence'),
      minTrackingConfidence: settings.share('minTrackingConfidence'),
      // Scored in the Output card, as Google's demo lists them.
      outputFaceBlendshapes: true,
    ),
  );
}

/// Browser transport for the same public HandLandmarker task. Hands counts
/// hands, not people, as in the native demo.
final class HandLandmarkerLiveTask extends _WebLiveTask<HandLandmarkerResult> {
  @override
  final settings = TaskSettingValues('hand_landmarker');

  @override
  String get name => 'Hand Landmarker';

  @override
  Future<HandLandmarker> create(
    VisionDelegate delegate,
    Uint8List model,
    RunningMode mode,
  ) => HandLandmarker.create(
    HandLandmarkerOptions(
      modelBytes: model,
      runningMode: mode,
      delegate: delegate,
      numHands: settings.count('numHands'),
      minHandDetectionConfidence: settings.share('minHandDetectionConfidence'),
      minHandPresenceConfidence: settings.share('minHandPresenceConfidence'),
      minTrackingConfidence: settings.share('minTrackingConfidence'),
    ),
  );
}

/// Browser transport for the same public PoseLandmarker task.
final class PoseLandmarkerLiveTask extends _WebLiveTask<PoseLandmarkerResult> {
  @override
  final settings = TaskSettingValues('pose_landmarker');

  @override
  String get name => 'Pose Landmarker';

  @override
  Future<PoseLandmarker> create(
    VisionDelegate delegate,
    Uint8List model,
    RunningMode mode,
  ) => PoseLandmarker.create(
    PoseLandmarkerOptions(
      modelBytes: model,
      runningMode: mode,
      delegate: delegate,
      numPoses: settings.count('numPoses'),
      minPoseDetectionConfidence: settings.share('minPoseDetectionConfidence'),
      minPosePresenceConfidence: settings.share('minPosePresenceConfidence'),
      minTrackingConfidence: settings.share('minTrackingConfidence'),
      outputSegmentationMasks: settings.on('outputSegmentationMasks'),
    ),
  );
}

/// Browser transport for the same public GestureRecognizer task.
final class GestureRecognizerLiveTask
    extends _WebLiveTask<GestureRecognizerResult> {
  @override
  final settings = TaskSettingValues('gesture_recognizer');

  @override
  String get name => 'Gesture Recognizer';

  @override
  Future<GestureRecognizer> create(
    VisionDelegate delegate,
    Uint8List model,
    RunningMode mode,
  ) => GestureRecognizer.create(
    GestureRecognizerOptions(
      modelBytes: model,
      runningMode: mode,
      delegate: delegate,
      numHands: settings.count('numHands'),
      minHandDetectionConfidence: settings.share('minHandDetectionConfidence'),
      minHandPresenceConfidence: settings.share('minHandPresenceConfidence'),
      minTrackingConfidence: settings.share('minTrackingConfidence'),
      cannedGesturesClassifierOptions: GestureClassifierOptions(
        maxResults: settings.count('maxResults'),
        scoreThreshold: settings.share('scoreThreshold'),
      ),
    ),
  );
}

/// Browser transport for the same public HolisticLandmarker task.
final class HolisticLandmarkerLiveTask
    extends _WebLiveTask<HolisticLandmarkerResult>
    implements FixedFrameSizeLiveTask {
  @override
  final settings = TaskSettingValues('holistic_landmarker');

  @override
  String get name => 'Holistic Landmarker';

  @override
  Future<HolisticLandmarker> create(
    VisionDelegate delegate,
    Uint8List model,
    RunningMode mode,
  ) => HolisticLandmarker.create(
    HolisticLandmarkerOptions(
      modelBytes: model,
      runningMode: mode,
      delegate: delegate,
      minFaceDetectionConfidence: settings.share('minFaceDetectionConfidence'),
      minFaceSuppressionThreshold: settings.share(
        'minFaceSuppressionThreshold',
      ),
      minFacePresenceConfidence: settings.share('minFacePresenceConfidence'),
      minPoseDetectionConfidence: settings.share('minPoseDetectionConfidence'),
      minPoseSuppressionThreshold: settings.share(
        'minPoseSuppressionThreshold',
      ),
      minPosePresenceConfidence: settings.share('minPosePresenceConfidence'),
      minHandLandmarksConfidence: settings.share('minHandLandmarksConfidence'),
      outputPoseSegmentationMask: settings.on('outputPoseSegmentationMask'),
    ),
  );
}

/// Browser transport for the same public FaceDetector task.
final class FaceDetectorLiveTask extends _WebLiveTask<FaceDetectorResult> {
  @override
  final settings = TaskSettingValues('face_detector');

  @override
  String get name => 'Face Detector';

  @override
  Future<FaceDetector> create(
    VisionDelegate delegate,
    Uint8List model,
    RunningMode mode,
  ) => FaceDetector.create(
    FaceDetectorOptions(
      modelBytes: model,
      runningMode: mode,
      delegate: delegate,
      minDetectionConfidence: settings.share('minDetectionConfidence'),
      minSuppressionThreshold: settings.share('minSuppressionThreshold'),
    ),
  );
}

/// Browser transport for the same public ObjectDetector task.
final class ObjectDetectorLiveTask extends _WebLiveTask<ObjectDetectorResult> {
  @override
  final settings = TaskSettingValues('object_detector');

  @override
  String get name => 'Object Detector';

  @override
  Future<ObjectDetector> create(
    VisionDelegate delegate,
    Uint8List model,
    RunningMode mode,
  ) => ObjectDetector.create(
    ObjectDetectorOptions(
      modelBytes: model,
      runningMode: mode,
      delegate: delegate,
      maxResults: settings.count('maxResults'),
      scoreThreshold: settings.share('scoreThreshold'),
    ),
  );
}

/// Browser transport for the same public ImageClassifier task.
final class ImageClassifierLiveTask
    extends _WebLiveTask<ImageClassifierResult> {
  @override
  final settings = TaskSettingValues('image_classifier');

  @override
  String get name => 'Image Classifier';

  @override
  Future<ImageClassifier> create(
    VisionDelegate delegate,
    Uint8List model,
    RunningMode mode,
  ) => ImageClassifier.create(
    ImageClassifierOptions(
      modelBytes: model,
      runningMode: mode,
      delegate: delegate,
      maxResults: settings.count('maxResults'),
      scoreThreshold: settings.share('scoreThreshold'),
    ),
  );
}

/// Browser Image Segmenter, returning the category mask and, for Output
/// Type Confidence Mask, the confidence masks.
final class ImageSegmenterLiveTask
    implements BrowserLiveTask<SegmentationResult> {
  @override
  final settings = TaskSettingValues('image_segmenter');

  ImageSegmenter? _task;

  @override
  String get name => 'Image Segmenter';

  @override
  Future<void> open(
    VisionDelegate delegate,
    Uint8List modelBytes, {
    RunningMode mode = RunningMode.video,
  }) async {
    _task = await ImageSegmenter.create(
      ImageSegmenterOptions(
        modelBytes: modelBytes,
        runningMode: mode,
        delegate: delegate,
        outputConfidenceMasks: settings.choice('outputConfidenceMasks') == 1,
        outputCategoryMask: true,
      ),
    );
  }

  @override
  Future<SegmentationResult> detectImage(VisionImage image) =>
      _task!.segmentImage(image);

  @override
  Future<SegmentationResult> detect(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.segmentForVideo(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  Future<SegmentationResult> detectBrowserFrame(
    Object frame,
    int width,
    int height,
    int timestamp,
  ) => (_task! as BrowserVisionTask<SegmentationResult>).detectBrowserFrame(
    frame,
    width: width,
    height: height,
    timestampMilliseconds: timestamp,
  );

  @override
  Future<void> close() async {
    final task = _task;
    _task = null;
    await task?.dispose();
  }
}
