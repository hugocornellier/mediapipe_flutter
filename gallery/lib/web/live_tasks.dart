import 'dart:typed_data';
import 'package:mediapipe_flutter_vision/web.dart';
import '../live/embedding_similarity.dart';
import '../live/live_task.dart';
import '../live/task_settings.dart';

/// Browser transport shared by every public task on the official web adapter:
/// each demo supplies only its name and how its task is built.
abstract base class _WebLiveTask<R> implements BrowserLiveTask<R> {
  SdkVisionTask<R>? _task;

  /// Creates the VIDEO-mode task.
  Future<SdkVisionTask<R>> create(VisionDelegate delegate, Uint8List model);

  @override
  Future<void> open(VisionDelegate delegate, Uint8List modelBytes) async {
    _task = await create(delegate, modelBytes);
  }

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
  ) => FaceLandmarker.create(
    FaceLandmarkerOptions(
      modelBytes: model,
      runningMode: VisionRunningMode.video,
      delegate: delegate,
      numFaces: settings.count('numFaces'),
      minFaceDetectionConfidence: settings.share('minFaceDetectionConfidence'),
      minFacePresenceConfidence: settings.share('minFacePresenceConfidence'),
      minTrackingConfidence: settings.share('minTrackingConfidence'),
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
  ) => HandLandmarker.create(
    HandLandmarkerOptions(
      modelBytes: model,
      runningMode: VisionRunningMode.video,
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
  ) => PoseLandmarker.create(
    PoseLandmarkerOptions(
      modelBytes: model,
      runningMode: VisionRunningMode.video,
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
  ) => GestureRecognizer.create(
    GestureRecognizerOptions(
      modelBytes: model,
      runningMode: VisionRunningMode.video,
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
    extends _WebLiveTask<HolisticLandmarkerResult> {
  @override
  final settings = TaskSettingValues('holistic_landmarker');

  @override
  String get name => 'Holistic Landmarker';

  @override
  Future<HolisticLandmarker> create(
    VisionDelegate delegate,
    Uint8List model,
  ) => HolisticLandmarker.create(
    HolisticLandmarkerOptions(
      modelBytes: model,
      runningMode: VisionRunningMode.video,
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
  Future<FaceDetector> create(VisionDelegate delegate, Uint8List model) =>
      FaceDetector.create(
        FaceDetectorOptions(
          modelBytes: model,
          runningMode: VisionRunningMode.video,
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
  Future<ObjectDetector> create(VisionDelegate delegate, Uint8List model) =>
      ObjectDetector.create(
        ObjectDetectorOptions(
          modelBytes: model,
          runningMode: VisionRunningMode.video,
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
  Future<ImageClassifier> create(VisionDelegate delegate, Uint8List model) =>
      ImageClassifier.create(
        ImageClassifierOptions(
          modelBytes: model,
          runningMode: VisionRunningMode.video,
          delegate: delegate,
          maxResults: settings.count('maxResults'),
          scoreThreshold: settings.share('scoreThreshold'),
        ),
      );
}

/// Browser Image Embedder, reporting each frame's similarity to the first.
final class ImageEmbedderLiveTask
    implements BrowserLiveTask<EmbeddingSimilarity>, StatefulLiveTask {
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
        modelBytes: modelBytes,
        runningMode: VisionRunningMode.video,
        delegate: delegate,
        l2Normalize: settings.on('l2Normalize'),
        quantize: settings.on('quantize'),
      ),
    );
  }

  EmbeddingSimilarity _compare(ImageEmbedderResult result) {
    final embedding = result.embeddings.first;
    final first = _first ??= embedding;
    return EmbeddingSimilarity(
      result,
      ImageEmbedder.cosineSimilarity(first, embedding),
    );
  }

  @override
  Future<EmbeddingSimilarity> detect(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) async => _compare(
    await _task!.embedForVideo(
      frame,
      timestampMilliseconds: timestamp,
      rotationDegrees: rotationDegrees,
    ),
  );

  @override
  Future<EmbeddingSimilarity> detectBrowserFrame(
    Object frame,
    int width,
    int height,
    int timestamp,
  ) async => _compare(
    await _task!.detectBrowserFrame(
      frame,
      width: width,
      height: height,
      timestampMilliseconds: timestamp,
    ),
  );

  @override
  Future<void> close() async {
    final task = _task;
    _task = null;
    await task?.dispose();
  }
}

/// Browser Image Segmenter, returning only the category mask the overlay
/// draws.
final class ImageSegmenterLiveTask
    implements BrowserLiveTask<SegmentationResult> {
  @override
  final settings = TaskSettingValues('image_segmenter');

  ImageSegmenter? _task;

  @override
  String get name => 'Image Segmenter';

  @override
  Future<void> open(VisionDelegate delegate, Uint8List modelBytes) async {
    _task = await ImageSegmenter.create(
      ImageSegmenterOptions(
        modelBytes: modelBytes,
        runningMode: VisionRunningMode.video,
        delegate: delegate,
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
  Future<SegmentationResult> detectBrowserFrame(
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
  Future<void> close() async {
    final task = _task;
    _task = null;
    await task?.dispose();
  }
}
