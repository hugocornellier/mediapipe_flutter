import 'dart:typed_data';

import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

import 'embedding_similarity.dart';
import 'live_camera_controller.dart';
import 'task_settings.dart';

/// Each adapter is only the two things that differ between live demos: how the
/// task is built, and how one frame runs through it.
final class FaceLandmarkerLiveTask implements LiveTask<FaceLandmarkerResult> {
  @override
  final settings = TaskSettingValues('face_landmarker');

  FaceLandmarker? _task;

  @override
  String get name => 'Face Landmarker';

  @override
  Future<void> open(VisionDelegate delegate, Uint8List modelBytes) async {
    _task = await FaceLandmarker.create(
      FaceLandmarkerOptions(
        delegate: delegate,
        modelBytes: modelBytes,
        runningMode: VisionRunningMode.video,
        numFaces: settings.count('numFaces'),
        minFaceDetectionConfidence: settings.share(
          'minFaceDetectionConfidence',
        ),
        minFacePresenceConfidence: settings.share('minFacePresenceConfidence'),
        minTrackingConfidence: settings.share('minTrackingConfidence'),
      ),
    );
  }

  @override
  Future<FaceLandmarkerResult> detect(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.detectForVideo(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

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
  Future<void> open(VisionDelegate delegate, Uint8List modelBytes) async {
    _task = await HandLandmarker.create(
      HandLandmarkerOptions(
        delegate: delegate,
        modelBytes: modelBytes,
        runningMode: VisionRunningMode.video,
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
  Future<HandLandmarkerResult> detect(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.detectForVideo(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

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
  Future<void> open(VisionDelegate delegate, Uint8List modelBytes) async {
    _task = await GestureRecognizer.create(
      GestureRecognizerOptions(
        delegate: delegate,
        modelBytes: modelBytes,
        runningMode: VisionRunningMode.video,
        numHands: settings.count('numHands'),
        minHandDetectionConfidence: settings.share(
          'minHandDetectionConfidence',
        ),
        minHandPresenceConfidence: settings.share('minHandPresenceConfidence'),
        minTrackingConfidence: settings.share('minTrackingConfidence'),
        cannedGesturesClassifierOptions: GestureClassifierOptions(
          maxResults: settings.count('maxResults'),
          scoreThreshold: settings.share('scoreThreshold'),
        ),
      ),
    );
  }

  @override
  Future<GestureRecognizerResult> detect(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.recognizeForVideo(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  Future<void> close() async {
    final task = _task;
    _task = null;
    await task?.dispose();
  }
}

final class HolisticLandmarkerLiveTask
    implements LiveTask<HolisticLandmarkerResult> {
  @override
  final settings = TaskSettingValues('holistic_landmarker');

  HolisticLandmarker? _task;

  @override
  String get name => 'Holistic Landmarker';

  @override
  Future<void> open(VisionDelegate delegate, Uint8List modelBytes) async {
    _task = await HolisticLandmarker.create(
      HolisticLandmarkerOptions(
        delegate: delegate,
        modelBytes: modelBytes,
        runningMode: VisionRunningMode.video,
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
  Future<HolisticLandmarkerResult> detect(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.detectForVideo(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

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
  Future<void> open(VisionDelegate delegate, Uint8List modelBytes) async {
    _task = await PoseLandmarker.create(
      PoseLandmarkerOptions(
        delegate: delegate,
        modelBytes: modelBytes,
        runningMode: VisionRunningMode.video,
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
  Future<PoseLandmarkerResult> detect(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.detectForVideo(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

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
  Future<void> open(VisionDelegate delegate, Uint8List modelBytes) async {
    _task = await FaceDetector.create(
      FaceDetectorOptions(
        delegate: delegate,
        modelBytes: modelBytes,
        runningMode: VisionRunningMode.video,
        minDetectionConfidence: settings.share('minDetectionConfidence'),
        minSuppressionThreshold: settings.share('minSuppressionThreshold'),
      ),
    );
  }

  @override
  Future<FaceDetectorResult> detect(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.detectForVideo(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

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
  Future<void> open(VisionDelegate delegate, Uint8List modelBytes) async {
    _task = await ObjectDetector.create(
      ObjectDetectorOptions(
        delegate: delegate,
        modelBytes: modelBytes,
        runningMode: VisionRunningMode.video,
        maxResults: settings.count('maxResults'),
        scoreThreshold: settings.share('scoreThreshold'),
      ),
    );
  }

  @override
  Future<ObjectDetectorResult> detect(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.detectForVideo(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

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
  Future<void> open(VisionDelegate delegate, Uint8List modelBytes) async {
    _task = await ImageClassifier.create(
      ImageClassifierOptions(
        delegate: delegate,
        modelBytes: modelBytes,
        runningMode: VisionRunningMode.video,
        maxResults: settings.count('maxResults'),
        scoreThreshold: settings.share('scoreThreshold'),
      ),
    );
  }

  @override
  Future<ImageClassifierResult> detect(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.classifyForVideo(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  Future<void> close() async {
    final task = _task;
    _task = null;
    await task?.dispose();
  }
}

/// Image Embedder, reporting each frame's similarity to the first one.
final class ImageEmbedderLiveTask
    implements LiveTask<EmbeddingSimilarity>, StatefulLiveTask {
  @override
  final settings = TaskSettingValues('image_embedder');

  ImageEmbedder? _task;
  VisionEmbedding? _first;

  @override
  void forgetFrames() => _first = null;

  @override
  String get name => 'Image Embedder';

  @override
  Future<void> open(VisionDelegate delegate, Uint8List modelBytes) async {
    _first = null;
    _task = await ImageEmbedder.create(
      ImageEmbedderOptions(
        delegate: delegate,
        modelBytes: modelBytes,
        runningMode: VisionRunningMode.video,
        l2Normalize: settings.on('l2Normalize'),
        quantize: settings.on('quantize'),
      ),
    );
  }

  @override
  Future<EmbeddingSimilarity> detect(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) async {
    final result = await _task!.embedForVideo(
      frame,
      timestampMilliseconds: timestamp,
      rotationDegrees: rotationDegrees,
    );
    final embedding = result.embeddings.first;
    final first = _first ??= embedding;
    return EmbeddingSimilarity(
      result,
      ImageEmbedder.cosineSimilarity(first, embedding),
    );
  }

  @override
  Future<void> close() async {
    final task = _task;
    _task = null;
    await task?.dispose();
  }
}

/// Image Segmenter, returning only the category mask the overlay draws.
final class ImageSegmenterLiveTask implements LiveTask<SegmentationResult> {
  @override
  final settings = TaskSettingValues('image_segmenter');

  ImageSegmenter? _task;

  @override
  String get name => 'Image Segmenter';

  @override
  Future<void> open(VisionDelegate delegate, Uint8List modelBytes) async {
    _task = await ImageSegmenter.create(
      ImageSegmenterOptions(
        delegate: delegate,
        modelBytes: modelBytes,
        runningMode: VisionRunningMode.video,
        outputConfidenceMasks: false,
        outputCategoryMask: true,
      ),
    );
  }

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
  Future<void> close() async {
    final task = _task;
    _task = null;
    await task?.dispose();
  }
}
