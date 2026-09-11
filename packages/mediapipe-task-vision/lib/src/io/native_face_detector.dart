import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../third_party/mediapipe/mediapipe_flutter_vision_bindings.dart'
    as mp;
import '../interface/face_detector_types.dart';

/// Internal synchronous owner, used exclusively by the detector's worker isolate.
final class NativeFaceDetector {
  /// Creates the official IMAGE-mode CPU task.
  NativeFaceDetector(FaceDetectorOptions options) {
    using((arena) {
      final native = arena<mp.MpFaceDetectorOptions>();
      final base = native.ref.base_options;
      base.file_descriptor = -1;
      base.delegate = mp.MpDelegate.MP_DELEGATE_CPU;
      base.host_system = mp.MpHostSystem.MP_HOST_SYSTEM_MAC;
      if (options.modelPath case final path?) {
        base.model_asset_path = path.toNativeUtf8(allocator: arena).cast();
      }
      if (options.modelBytes case final bytes?) {
        final buffer = arena<Uint8>(bytes.length);
        buffer.asTypedList(bytes.length).setAll(0, bytes);
        base.model_asset_buffer = buffer.cast();
        base.model_asset_buffer_count = bytes.length;
      }
      native.ref
        ..running_mode = mp.MpRunningMode.MP_RUNNING_MODE_IMAGE
        ..min_detection_confidence = options.minDetectionConfidence
        ..min_suppression_threshold = options.minSuppressionThreshold;
      final output = arena<mp.MpFaceDetectorPtr>();
      _checked((error) => mp.MpFaceDetectorCreate(native, output, error));
      _detector = output.value;
    });
  }

  mp.MpFaceDetectorPtr _detector = nullptr;

  /// Runs a single image and copies every result before releasing native memory.
  FaceDetectorResult detect(VisionImage input, int rotation) {
    return using((arena) {
      final imageOut = arena<mp.MpImagePtr>();
      if (input.path case final path?) {
        final name = path.toNativeUtf8(allocator: arena).cast<Char>();
        _checked((error) => mp.MpImageCreateFromFile(name, imageOut, error));
      } else {
        final bytes = input.pixels!;
        final pixels = arena<Uint8>(bytes.length);
        pixels.asTypedList(bytes.length).setAll(0, bytes);
        _checked(
          (error) => mp.MpImageCreateFromUint8Data(
            input.format == VisionPixelFormat.rgb
                ? mp.MpImageFormat.kMpImageFormatSrgb
                : mp.MpImageFormat.kMpImageFormatSrgba,
            input.width!,
            input.height!,
            pixels,
            bytes.length,
            imageOut,
            error,
          ),
        );
      }
      final image = imageOut.value;
      try {
        final options = arena<mp.MpImageProcessingOptions>();
        options.ref.rotation_degrees = rotation;
        final result = arena<mp.MpFaceDetectorResult>();
        _checked(
          (error) => mp.MpFaceDetectorDetectImage(
            _detector,
            image,
            options,
            result,
            error,
          ),
        );
        try {
          return FaceDetectorResult(
            imageWidth: mp.MpImageGetWidth(image),
            imageHeight: mp.MpImageGetHeight(image),
            detections: [
              for (var i = 0; i < result.ref.detections_count; i++)
                _copyDetection(result.ref.detections[i]),
            ],
          );
        } finally {
          // This releases the contents, while Arena owns the outer struct.
          mp.MpFaceDetectorCloseResult(result);
        }
      } finally {
        mp.MpImageFree(image);
      }
    });
  }

  /// Closes the task exactly once, including when native shutdown reports failure.
  void close() {
    if (_detector == nullptr) return;
    final pointer = _detector;
    _detector = nullptr;
    _checked((error) => mp.MpFaceDetectorClose(pointer, error));
  }
}

void _checked(mp.MpStatus Function(Pointer<Pointer<Char>>) call) {
  final error = calloc<Pointer<Char>>();
  try {
    final status = call(error);
    if (status != mp.MpStatus.kMpOk) {
      throw FaceDetectorException(
        _string(error.value) ?? 'MediaPipe returned ${status.name}',
        statusCode: status.value,
      );
    }
  } finally {
    if (error.value != nullptr) mp.MpErrorFree(error.value);
    calloc.free(error);
  }
}

String? _string(Pointer<Char> pointer) {
  if (pointer == nullptr) return null;
  final value = pointer.cast<Utf8>().toDartString();
  // The official Python API treats empty optional C strings as absent.
  return value.isEmpty ? null : value;
}

FaceDetection _copyDetection(mp.MpDetection value) => FaceDetection(
  boundingBox: FaceBoundingBox(
    left: value.bounding_box.left,
    top: value.bounding_box.top,
    right: value.bounding_box.right,
    bottom: value.bounding_box.bottom,
  ),
  categories: [
    for (var i = 0; i < value.categories_count; i++)
      FaceCategory(
        index: value.categories[i].index,
        score: value.categories[i].score,
        categoryName: _string(value.categories[i].category_name),
        displayName: _string(value.categories[i].display_name),
      ),
  ],
  keypoints: [
    for (var i = 0; i < value.keypoints_count; i++)
      FaceKeypoint(
        x: value.keypoints[i].x,
        y: value.keypoints[i].y,
        label: _string(value.keypoints[i].label),
        score: value.keypoints[i].has_score ? value.keypoints[i].score : null,
      ),
  ],
);
