import 'dart:typed_data';

import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

import 'embedding_similarity.dart';
import 'live_camera_controller.dart';

/// Subjects each live demo tracks. Ask for what the demo needs and no more:
/// MediaPipe only skips its detector once tracking reaches the configured
/// maximum, so an inflated count keeps detection running every frame for a
/// scene that never reaches it. Hands counts hands, not people.
const _faces = 1;
const _hands = 2;
const _poses = 1;

/// Each adapter is only the two things that differ between live demos: how the
/// task is built, and how one frame runs through it.
final class FaceLandmarkerLiveTask implements LiveTask<FaceLandmarkerResult> {
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
        numFaces: _faces,
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
        numHands: _hands,
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
        numHands: 2,
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
        numPoses: _poses,
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
        maxResults: 5,
        scoreThreshold: 0.3,
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
        maxResults: 3,
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
final class ImageEmbedderLiveTask implements LiveTask<EmbeddingSimilarity> {
  ImageEmbedder? _task;
  VisionEmbedding? _first;

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
