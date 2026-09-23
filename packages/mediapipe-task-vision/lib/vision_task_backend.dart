/// Extension point for platform SDK adapters. Applications use the task classes.
library;

import 'src/interface/face_detector_types.dart';
import 'src/interface/holistic_landmarker_types.dart';
import 'src/interface/image_classifier_types.dart';
import 'src/interface/image_embedder_types.dart';
import 'src/interface/interactive_segmenter_types.dart';
import 'src/interface/object_detector_types.dart';
import 'src/interface/segmenter_task_types.dart';

export 'src/interface/face_detector_types.dart';
export 'src/interface/holistic_landmarker_types.dart';
export 'src/interface/image_classifier_types.dart';
export 'src/interface/image_embedder_types.dart';
export 'src/interface/interactive_segmenter_types.dart';
export 'src/interface/object_detector_types.dart';
export 'src/interface/segmenter_task_types.dart';
export 'src/interface/landmark_codec.dart';

/// A serialized, asynchronous adapter to one task of an official platform SDK.
abstract interface class VisionTaskBackend<R> {
  /// Completes with copied results; requests and disposal retain submission order.
  /// Only tasks that accept a region of interest receive [regionOfInterest],
  /// and only Interactive Segmenter Legacy receives its [keypoint].
  Future<R> detect(
    VisionImage image,
    int rotationDegrees,
    int? timestampMilliseconds, {
    VisionRegionOfInterest? regionOfInterest,
    SegmentationPoint? keypoint,
  });

  /// Finishes queued requests and releases the SDK task on its owning thread.
  Future<void> dispose();
}

/// Optional browser-frame transport, keeping browser objects out of native APIs.
abstract interface class VisionTaskFrameBackend<R>
    implements VisionTaskBackend<R> {
  /// Takes ownership of one browser frame and releases it after inference.
  Future<R> detectFrame(
    Object frame,
    int width,
    int height,
    int rotationDegrees,
    int timestampMilliseconds,
  );
}

/// Installed by a platform plugin before the first HandLandmarker is created.
Future<VisionTaskBackend<HandLandmarkerResult>> Function(HandLandmarkerOptions)?
handLandmarkerBackendFactory;

/// Installed by a platform plugin before the first PoseLandmarker is created.
Future<VisionTaskBackend<PoseLandmarkerResult>> Function(PoseLandmarkerOptions)?
poseLandmarkerBackendFactory;

/// Installed by a platform plugin before the first GestureRecognizer is created.
Future<VisionTaskBackend<GestureRecognizerResult>> Function(
  GestureRecognizerOptions,
)?
gestureRecognizerBackendFactory;

/// Installed by a platform plugin before the first HolisticLandmarker is created.
Future<VisionTaskBackend<HolisticLandmarkerResult>> Function(
  HolisticLandmarkerOptions,
)?
holisticLandmarkerBackendFactory;

/// Installed by a platform plugin before the first FaceDetector is created.
Future<VisionTaskBackend<FaceDetectorResult>> Function(FaceDetectorOptions)?
faceDetectorBackendFactory;

/// Installed by a platform plugin before the first ObjectDetector is created.
Future<VisionTaskBackend<ObjectDetectorResult>> Function(ObjectDetectorOptions)?
objectDetectorBackendFactory;

/// Installed by a platform plugin before the first ImageClassifier is created.
Future<VisionTaskBackend<ImageClassifierResult>> Function(
  ImageClassifierOptions,
)?
imageClassifierBackendFactory;

/// Installed by a platform plugin before the first ImageEmbedder is created.
Future<VisionTaskBackend<ImageEmbedderResult>> Function(ImageEmbedderOptions)?
imageEmbedderBackendFactory;

/// Installed by a platform plugin before the first ImageSegmenter is created.
Future<VisionTaskBackend<SegmentationResult>> Function(ImageSegmenterOptions)?
imageSegmenterBackendFactory;

/// One stateful Interactive Segmenter session on an official platform SDK:
/// an image, then complete stroke histories, in submission order.
abstract interface class InteractiveSegmenterBackend {
  /// Replaces the image and resets the stroke session.
  Future<void> setImage(VisionImage image);

  /// Segments with the full, nonempty stroke history.
  Future<SegmentationMask> segment(List<SegmentationStroke> strokes);

  /// Finishes queued requests and releases the SDK task.
  Future<void> dispose();
}

/// Installed by a platform plugin before the first InteractiveSegmenter is
/// created.
Future<InteractiveSegmenterBackend> Function(InteractiveSegmenterOptions)?
interactiveSegmenterBackendFactory;

/// Installed by a platform plugin before the first InteractiveSegmenterLegacy
/// is created.
Future<VisionTaskBackend<SegmentationResult>> Function(
  InteractiveSegmenterLegacyOptions,
)?
interactiveSegmenterLegacyBackendFactory;
