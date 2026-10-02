import 'dart:typed_data';

import 'package:mediapipe_vision/mediapipe_vision.dart';

import '../live/live_task.dart';
import '../live/task_settings.dart';

/// Browser transport shared by every public task on the official web adapter:
/// each demo supplies only its name and how its task is built.
abstract base class _WebLiveTask<R>
    implements BrowserLiveTask<R>, BrowserOverlayLiveTask {
  VisionTask? _task;
  BrowserOverlay? _overlay;

  /// Creates a task in the requested running mode.
  Future<VisionTask> create(
    Delegate delegate,
    Uint8List model,
    RunningMode mode,
  );

  @override
  Future<void> open(
    Delegate delegate,
    Uint8List modelBytes, {
    RunningMode mode = RunningMode.video,
  }) async {
    _task = await create(delegate, modelBytes, mode);
  }

  @override
  Future<R> detectImage(VisionImage image) =>
      switch (_task!) {
            final FaceLandmarker t => t.detect(image),
            final HandLandmarker t => t.detect(image),
            final PoseLandmarker t => t.detect(image),
            final GestureRecognizer t => t.recognize(image),
            final HolisticLandmarker t => t.detect(image),
            final FaceDetector t => t.detect(image),
            final ObjectDetector t => t.detect(image),
            final ImageClassifier t => t.classify(image),
            final ImageEmbedder t => t.embed(image),
            final ImageSegmenter t => t.segment(image),
            final task => throw UnsupportedError('$task has no still images.'),
          }
          as Future<R>;

  @override
  Future<R> detect(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) =>
      switch (_task!) {
            final FaceLandmarker t => t.detectForVideo(
              frame,
              timestampMilliseconds: timestamp,
              rotationDegrees: rotationDegrees,
            ),
            final HandLandmarker t => t.detectForVideo(
              frame,
              timestampMilliseconds: timestamp,
              rotationDegrees: rotationDegrees,
            ),
            final PoseLandmarker t => t.detectForVideo(
              frame,
              timestampMilliseconds: timestamp,
              rotationDegrees: rotationDegrees,
            ),
            final GestureRecognizer t => t.recognizeForVideo(
              frame,
              timestampMilliseconds: timestamp,
              rotationDegrees: rotationDegrees,
            ),
            final HolisticLandmarker t => t.detectForVideo(
              frame,
              timestampMilliseconds: timestamp,
              rotationDegrees: rotationDegrees,
            ),
            final FaceDetector t => t.detectForVideo(
              frame,
              timestampMilliseconds: timestamp,
              rotationDegrees: rotationDegrees,
            ),
            final ObjectDetector t => t.detectForVideo(
              frame,
              timestampMilliseconds: timestamp,
              rotationDegrees: rotationDegrees,
            ),
            final ImageClassifier t => t.classifyForVideo(
              frame,
              timestampMilliseconds: timestamp,
              rotationDegrees: rotationDegrees,
            ),
            final ImageEmbedder t => t.embedForVideo(
              frame,
              timestampMilliseconds: timestamp,
              rotationDegrees: rotationDegrees,
            ),
            final ImageSegmenter t => t.segmentForVideo(
              frame,
              timestampMilliseconds: timestamp,
              rotationDegrees: rotationDegrees,
            ),
            final task => throw UnsupportedError('$task has no video mode.'),
          }
          as Future<R>;

  @override
  Future<R> detectBrowserFrame(
    Object frame,
    int width,
    int height,
    int timestamp,
  ) => detect(
    VisionImage.fromBrowserFrame(frame, width: width, height: height),
    timestamp,
    rotationDegrees: 0,
  );

  @override
  Future<void> attachOverlay(Object canvas) async {
    _overlay = await BrowserOverlay.attach(_task!, canvas);
  }

  @override
  void setOverlayOptions({
    required bool connections,
    required bool points,
    required bool mirrored,
    required double scale,
  }) => _overlay?.configure(
    connections: connections,
    points: points,
    mirrored: mirrored,
    scale: scale,
  );

  @override
  bool get overlayActive => _overlay?.active ?? false;

  @override
  Future<void> close() async {
    final task = _task;
    _task = null;
    _overlay = null;
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
    Delegate delegate,
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
    Delegate delegate,
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
    Delegate delegate,
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
    Delegate delegate,
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
      cannedGesturesClassifierOptions: ClassifierOptions(
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
    Delegate delegate,
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
    Delegate delegate,
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
    Delegate delegate,
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
    Delegate delegate,
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
    implements BrowserLiveTask<ImageSegmenterResult> {
  @override
  final settings = TaskSettingValues('image_segmenter');

  ImageSegmenter? _task;

  @override
  String get name => 'Image Segmenter';

  @override
  Future<void> open(
    Delegate delegate,
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
  Future<ImageSegmenterResult> detectImage(VisionImage image) =>
      _task!.segment(image);

  @override
  Future<ImageSegmenterResult> detect(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.segmentForVideo(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  Future<ImageSegmenterResult> detectBrowserFrame(
    Object frame,
    int width,
    int height,
    int timestamp,
  ) => _task!.segmentForVideo(
    VisionImage.fromBrowserFrame(frame, width: width, height: height),
    timestampMilliseconds: timestamp,
  );

  @override
  Future<void> close() async {
    final task = _task;
    _task = null;
    await task?.dispose();
  }
}
