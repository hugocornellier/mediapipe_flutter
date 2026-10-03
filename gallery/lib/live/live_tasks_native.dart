import 'dart:typed_data';

import 'package:mediapipe_vision/mediapipe_vision.dart';

import 'live_camera_controller.dart';
import 'task_settings.dart';

/// Each adapter is only the two things that differ between live demos: how the
/// task is built, and which of its methods takes a frame.
final class FaceLandmarkerLiveTask implements LiveTask<FaceLandmarkerResult> {
  @override
  final settings = TaskSettingValues('face_landmarker');

  FaceLandmarker? _task;

  @override
  String get name => 'Face Landmarker';

  @override
  Future<void> open(
    Delegate delegate,
    Uint8List modelBytes, {
    RunningMode mode = RunningMode.liveStream,
  }) async {
    _task = await FaceLandmarker.create(
      FaceLandmarkerOptions(
        delegate: delegate,
        modelBytes: modelBytes,
        runningMode: mode,
        numFaces: settings.count('numFaces'),
        minFaceDetectionConfidence: settings.share(
          'minFaceDetectionConfidence',
        ),
        minFacePresenceConfidence: settings.share('minFacePresenceConfidence'),
        minTrackingConfidence: settings.share('minTrackingConfidence'),
        // Scored in the Output card, as Google's demo lists them.
        outputFaceBlendshapes: true,
      ),
    );
  }

  @override
  Future<FaceLandmarkerResult> detectImage(VisionImage image) =>
      _task!.detect(image);

  @override
  Future<FaceLandmarkerResult> detectFrame(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.detectForVideo(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  void submit(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.detectAsync(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  Stream<LiveResult<FaceLandmarkerResult>> get results => _task!.results.map(
    (result) => (timestamp: result.timestampMilliseconds!, result: result),
  );

  @override
  int get droppedFrames => _task?.droppedFrames ?? 0;

  @override
  Future<void> close() async {
    final task = _task;
    _task = null;
    await task?.dispose();
  }
}

final class HandLandmarkerLiveTask implements LiveTask<HandLandmarkerResult> {
  @override
  final settings = TaskSettingValues('hand_landmarker');

  HandLandmarker? _task;

  @override
  String get name => 'Hand Landmarker';

  @override
  Future<void> open(
    Delegate delegate,
    Uint8List modelBytes, {
    RunningMode mode = RunningMode.liveStream,
  }) async {
    _task = await HandLandmarker.create(
      HandLandmarkerOptions(
        delegate: delegate,
        modelBytes: modelBytes,
        runningMode: mode,
        numHands: settings.count('numHands'),
        minHandDetectionConfidence: settings.share(
          'minHandDetectionConfidence',
        ),
        minHandPresenceConfidence: settings.share('minHandPresenceConfidence'),
        minTrackingConfidence: settings.share('minTrackingConfidence'),
      ),
    );
  }

  @override
  Future<HandLandmarkerResult> detectImage(VisionImage image) =>
      _task!.detect(image);

  @override
  Future<HandLandmarkerResult> detectFrame(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.detectForVideo(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  void submit(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.detectAsync(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  Stream<LiveResult<HandLandmarkerResult>> get results => _task!.results.map(
    (result) => (timestamp: result.timestampMilliseconds!, result: result),
  );

  @override
  int get droppedFrames => _task?.droppedFrames ?? 0;

  @override
  Future<void> close() async {
    final task = _task;
    _task = null;
    await task?.dispose();
  }
}

final class GestureRecognizerLiveTask
    implements LiveTask<GestureRecognizerResult> {
  @override
  final settings = TaskSettingValues('gesture_recognizer');

  GestureRecognizer? _task;

  @override
  String get name => 'Gesture Recognizer';

  @override
  Future<void> open(
    Delegate delegate,
    Uint8List modelBytes, {
    RunningMode mode = RunningMode.liveStream,
  }) async {
    _task = await GestureRecognizer.create(
      GestureRecognizerOptions(
        delegate: delegate,
        modelBytes: modelBytes,
        runningMode: mode,
        numHands: settings.count('numHands'),
        minHandDetectionConfidence: settings.share(
          'minHandDetectionConfidence',
        ),
        minHandPresenceConfidence: settings.share('minHandPresenceConfidence'),
        minTrackingConfidence: settings.share('minTrackingConfidence'),
        cannedGesturesClassifierOptions: ClassifierOptions(
          maxResults: settings.count('maxResults'),
          scoreThreshold: settings.share('scoreThreshold'),
        ),
      ),
    );
  }

  @override
  Future<GestureRecognizerResult> detectImage(VisionImage image) =>
      _task!.recognize(image);

  @override
  Future<GestureRecognizerResult> detectFrame(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.recognizeForVideo(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  void submit(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.recognizeAsync(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  Stream<LiveResult<GestureRecognizerResult>> get results => _task!.results.map(
    (result) => (timestamp: result.timestampMilliseconds!, result: result),
  );

  @override
  int get droppedFrames => _task?.droppedFrames ?? 0;

  @override
  Future<void> close() async {
    final task = _task;
    _task = null;
    await task?.dispose();
  }
}

final class HolisticLandmarkerLiveTask
    implements LiveTask<HolisticLandmarkerResult>, FixedFrameSizeLiveTask {
  @override
  final settings = TaskSettingValues('holistic_landmarker');

  HolisticLandmarker? _task;

  @override
  String get name => 'Holistic Landmarker';

  @override
  Future<void> open(
    Delegate delegate,
    Uint8List modelBytes, {
    RunningMode mode = RunningMode.liveStream,
  }) async {
    _task = await HolisticLandmarker.create(
      HolisticLandmarkerOptions(
        delegate: delegate,
        modelBytes: modelBytes,
        runningMode: mode,
        minFaceDetectionConfidence: settings.share(
          'minFaceDetectionConfidence',
        ),
        minFaceSuppressionThreshold: settings.share(
          'minFaceSuppressionThreshold',
        ),
        minFacePresenceConfidence: settings.share('minFacePresenceConfidence'),
        minPoseDetectionConfidence: settings.share(
          'minPoseDetectionConfidence',
        ),
        minPoseSuppressionThreshold: settings.share(
          'minPoseSuppressionThreshold',
        ),
        minPosePresenceConfidence: settings.share('minPosePresenceConfidence'),
        minHandLandmarksConfidence: settings.share(
          'minHandLandmarksConfidence',
        ),
        outputPoseSegmentationMask: settings.on('outputPoseSegmentationMask'),
      ),
    );
  }

  @override
  Future<HolisticLandmarkerResult> detectImage(VisionImage image) =>
      _task!.detect(image);

  @override
  Future<HolisticLandmarkerResult> detectFrame(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.detectForVideo(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  void submit(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.detectAsync(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  Stream<LiveResult<HolisticLandmarkerResult>> get results =>
      _task!.results.map(
        (result) => (timestamp: result.timestampMilliseconds!, result: result),
      );

  @override
  int get droppedFrames => _task?.droppedFrames ?? 0;

  @override
  Future<void> close() async {
    final task = _task;
    _task = null;
    await task?.dispose();
  }
}

final class PoseLandmarkerLiveTask implements LiveTask<PoseLandmarkerResult> {
  @override
  final settings = TaskSettingValues('pose_landmarker');

  PoseLandmarker? _task;

  @override
  String get name => 'Pose Landmarker';

  @override
  Future<void> open(
    Delegate delegate,
    Uint8List modelBytes, {
    RunningMode mode = RunningMode.liveStream,
  }) async {
    _task = await PoseLandmarker.create(
      PoseLandmarkerOptions(
        delegate: delegate,
        modelBytes: modelBytes,
        runningMode: mode,
        numPoses: settings.count('numPoses'),
        minPoseDetectionConfidence: settings.share(
          'minPoseDetectionConfidence',
        ),
        minPosePresenceConfidence: settings.share('minPosePresenceConfidence'),
        minTrackingConfidence: settings.share('minTrackingConfidence'),
        outputSegmentationMasks: settings.on('outputSegmentationMasks'),
      ),
    );
  }

  @override
  Future<PoseLandmarkerResult> detectImage(VisionImage image) =>
      _task!.detect(image);

  @override
  Future<PoseLandmarkerResult> detectFrame(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.detectForVideo(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  void submit(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.detectAsync(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  Stream<LiveResult<PoseLandmarkerResult>> get results => _task!.results.map(
    (result) => (timestamp: result.timestampMilliseconds!, result: result),
  );

  @override
  int get droppedFrames => _task?.droppedFrames ?? 0;

  @override
  Future<void> close() async {
    final task = _task;
    _task = null;
    await task?.dispose();
  }
}

final class FaceDetectorLiveTask implements LiveTask<FaceDetectorResult> {
  @override
  final settings = TaskSettingValues('face_detector');

  FaceDetector? _task;

  @override
  String get name => 'Face Detector';

  @override
  Future<void> open(
    Delegate delegate,
    Uint8List modelBytes, {
    RunningMode mode = RunningMode.liveStream,
  }) async {
    _task = await FaceDetector.create(
      FaceDetectorOptions(
        delegate: delegate,
        modelBytes: modelBytes,
        runningMode: mode,
        minDetectionConfidence: settings.share('minDetectionConfidence'),
        minSuppressionThreshold: settings.share('minSuppressionThreshold'),
      ),
    );
  }

  @override
  Future<FaceDetectorResult> detectImage(VisionImage image) =>
      _task!.detect(image);

  @override
  Future<FaceDetectorResult> detectFrame(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.detectForVideo(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  void submit(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.detectAsync(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  Stream<LiveResult<FaceDetectorResult>> get results => _task!.results.map(
    (result) => (timestamp: result.timestampMilliseconds!, result: result),
  );

  @override
  int get droppedFrames => _task?.droppedFrames ?? 0;

  @override
  Future<void> close() async {
    final task = _task;
    _task = null;
    await task?.dispose();
  }
}

final class ObjectDetectorLiveTask implements LiveTask<ObjectDetectorResult> {
  @override
  final settings = TaskSettingValues('object_detector');

  ObjectDetector? _task;

  @override
  String get name => 'Object Detector';

  @override
  Future<void> open(
    Delegate delegate,
    Uint8List modelBytes, {
    RunningMode mode = RunningMode.liveStream,
  }) async {
    _task = await ObjectDetector.create(
      ObjectDetectorOptions(
        delegate: delegate,
        modelBytes: modelBytes,
        runningMode: mode,
        maxResults: settings.count('maxResults'),
        scoreThreshold: settings.share('scoreThreshold'),
      ),
    );
  }

  @override
  Future<ObjectDetectorResult> detectImage(VisionImage image) =>
      _task!.detect(image);

  @override
  Future<ObjectDetectorResult> detectFrame(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.detectForVideo(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  void submit(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.detectAsync(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  Stream<LiveResult<ObjectDetectorResult>> get results => _task!.results.map(
    (result) => (timestamp: result.timestampMilliseconds!, result: result),
  );

  @override
  int get droppedFrames => _task?.droppedFrames ?? 0;

  @override
  Future<void> close() async {
    final task = _task;
    _task = null;
    await task?.dispose();
  }
}

final class ImageClassifierLiveTask implements LiveTask<ImageClassifierResult> {
  @override
  final settings = TaskSettingValues('image_classifier');

  ImageClassifier? _task;

  @override
  String get name => 'Image Classifier';

  @override
  Future<void> open(
    Delegate delegate,
    Uint8List modelBytes, {
    RunningMode mode = RunningMode.liveStream,
  }) async {
    _task = await ImageClassifier.create(
      ImageClassifierOptions(
        delegate: delegate,
        modelBytes: modelBytes,
        runningMode: mode,
        maxResults: settings.count('maxResults'),
        scoreThreshold: settings.share('scoreThreshold'),
      ),
    );
  }

  @override
  Future<ImageClassifierResult> detectImage(VisionImage image) =>
      _task!.classify(image);

  @override
  Future<ImageClassifierResult> detectFrame(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.classifyForVideo(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  void submit(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.classifyAsync(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  Stream<LiveResult<ImageClassifierResult>> get results => _task!.results.map(
    (result) => (timestamp: result.timestampMilliseconds!, result: result),
  );

  @override
  int get droppedFrames => _task?.droppedFrames ?? 0;

  @override
  Future<void> close() async {
    final task = _task;
    _task = null;
    await task?.dispose();
  }
}

/// Image Segmenter, returning the category mask and, for Output Type
/// Confidence Mask, the confidence masks.
final class ImageSegmenterLiveTask implements LiveTask<ImageSegmenterResult> {
  @override
  final settings = TaskSettingValues('image_segmenter');

  ImageSegmenter? _task;

  @override
  String get name => 'Image Segmenter';

  @override
  Future<void> open(
    Delegate delegate,
    Uint8List modelBytes, {
    RunningMode mode = RunningMode.liveStream,
  }) async {
    _task = await ImageSegmenter.create(
      ImageSegmenterOptions(
        delegate: delegate,
        modelBytes: modelBytes,
        runningMode: mode,
        outputConfidenceMasks: settings.choice('outputConfidenceMasks') == 1,
        outputCategoryMask: true,
      ),
    );
  }

  @override
  Future<ImageSegmenterResult> detectImage(VisionImage image) =>
      _task!.segment(image);

  @override
  Future<ImageSegmenterResult> detectFrame(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.segmentForVideo(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  void submit(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.segmentAsync(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  Stream<LiveResult<ImageSegmenterResult>> get results => _task!.results.map(
    (result) => (timestamp: result.timestampMilliseconds!, result: result),
  );

  @override
  int get droppedFrames => _task?.droppedFrames ?? 0;

  @override
  Future<void> close() async {
    final task = _task;
    _task = null;
    await task?.dispose();
  }
}
