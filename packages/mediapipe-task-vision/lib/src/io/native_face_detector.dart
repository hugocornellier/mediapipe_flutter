import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../third_party/mediapipe/mediapipe_flutter_vision_bindings.dart'
    as mp;
import '../interface/face_detector_types.dart';
import 'pixel_conversion.dart';
import 'native_ios_sdk.dart';
import 'native_desktop_runtime.dart';

/// Internal synchronous owner, used exclusively by the detector's worker isolate.
final class NativeFaceDetector {
  /// Creates the official IMAGE or VIDEO task with the requested delegate.
  NativeFaceDetector(FaceDetectorOptions options)
    : _gpu = options.delegate == VisionDelegate.gpu,
      _officialIos = hasOfficialIosFaceRuntime(detector: true) {
    if (!Platform.isMacOS && !Platform.isLinux && !_officialIos && _gpu) {
      throw UnsupportedError(
        'GPU face inference requires macOS, Linux or the official iOS SDK '
        'adapter; this runtime supports CPU only.',
      );
    }
    loadOfficialDesktopRuntime();
    using((arena) {
      final native = arena<mp.MpFaceDetectorOptions>();
      final base = native.ref.base_options;
      base.file_descriptor = -1;
      base.delegate = options.delegate == VisionDelegate.gpu
          ? mp.MpDelegate.MP_DELEGATE_GPU
          : mp.MpDelegate.MP_DELEGATE_CPU;
      base.host_system = Platform.isIOS
          ? mp.MpHostSystem.MP_HOST_SYSTEM_IOS
          : Platform.isAndroid
          ? mp.MpHostSystem.MP_HOST_SYSTEM_ANDROID
          : Platform.isLinux
          ? mp.MpHostSystem.MP_HOST_SYSTEM_LINUX
          : Platform.isWindows
          ? mp.MpHostSystem.MP_HOST_SYSTEM_WINDOWS
          : mp.MpHostSystem.MP_HOST_SYSTEM_MAC;
      if (options.modelPath case final path?) {
        // Android's resource resolver treats relative paths as Java assets.
        // This FFI API reads files, so bypass that resolver with a full path.
        final filePath = Platform.isAndroid ? File(path).absolute.path : path;
        base.model_asset_path = filePath.toNativeUtf8(allocator: arena).cast();
      }
      if (options.modelBytes case final bytes?) {
        final buffer = arena<Uint8>(bytes.length);
        buffer.asTypedList(bytes.length).setAll(0, bytes);
        base.model_asset_buffer = buffer.cast();
        base.model_asset_buffer_count = bytes.length;
      }
      native.ref
        ..running_mode = options.runningMode == VisionRunningMode.video
            ? mp.MpRunningMode.MP_RUNNING_MODE_VIDEO
            : mp.MpRunningMode.MP_RUNNING_MODE_IMAGE
        ..min_detection_confidence = options.minDetectionConfidence
        ..min_suppression_threshold = options.minSuppressionThreshold;
      final output = arena<mp.MpFaceDetectorPtr>();
      try {
        _checked((error) => mp.MpFaceDetectorCreate(native, output, error));
      } on FaceDetectorException catch (error) {
        // Google's runtime reports every GPU refusal (no EGL display, a
        // software renderer) as its missing GPU service.
        if (!_gpu || !error.message.contains('kGpuService')) rethrow;
        throw FaceDetectorException(
          error.message,
          statusCode: error.statusCode,
          gpuUnavailable: true,
        );
      }
      _detector = output.value;
    });
  }

  mp.MpFaceDetectorPtr _detector = nullptr;
  final bool _gpu;
  final bool _officialIos;

  /// Runs a single image and copies every result before releasing native memory.
  FaceDetectorResult detect(VisionImage input, int rotation, {int? timestamp}) {
    return using((arena) {
      final imageOut = arena<mp.MpImagePtr>();
      if (input.path case final path?) {
        final name = path.toNativeUtf8(allocator: arena).cast<Char>();
        _checked((error) => mp.MpImageCreateFromFile(name, imageOut, error));
      } else if (_officialIos && input.format == VisionPixelFormat.bgra) {
        _checked(
          (error) => mp.MpStatus.fromValue(
            createOfficialIosBgraImage(input, arena, imageOut.cast(), error),
          ),
        );
      } else {
        final bytes = input.pixels!;
        // Apple's GPU image upload cannot accept three-channel ImageFrames, so
        // GPU input gets opaque alpha on every host, as in the GPU references.
        final expandRgb =
            _gpu && !_officialIos && input.format == VisionPixelFormat.rgb;
        final rowSize = input.width! * (expandRgb ? 4 : input.format!.channels);
        final byteCount = rowSize * input.height!;
        final pixels = arena<Uint8>(byteCount);
        final packed = pixels.asTypedList(byteCount);
        if (expandRgb) {
          for (var y = 0; y < input.height!; y++) {
            for (var x = 0; x < input.width!; x++) {
              final source = y * input.bytesPerRow! + x * 3;
              final target = y * rowSize + x * 4;
              packed[target] = bytes[source];
              packed[target + 1] = bytes[source + 1];
              packed[target + 2] = bytes[source + 2];
              packed[target + 3] = 255;
            }
          }
        } else if (input.format == VisionPixelFormat.bgra) {
          copyBgraToRgba(
            source: bytes,
            target: packed,
            width: input.width!,
            height: input.height!,
            bytesPerRow: input.bytesPerRow!,
          );
        } else {
          for (var y = 0; y < input.height!; y++) {
            packed.setRange(
              y * rowSize,
              (y + 1) * rowSize,
              bytes,
              y * input.bytesPerRow!,
            );
          }
        }
        _checked(
          (error) => mp.MpImageCreateFromUint8Data(
            input.format == VisionPixelFormat.rgb && !expandRgb
                ? mp.MpImageFormat.kMpImageFormatSrgb
                : mp.MpImageFormat.kMpImageFormatSrgba,
            input.width!,
            input.height!,
            pixels,
            byteCount,
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
        if (timestamp == null) {
          _checked(
            (error) => mp.MpFaceDetectorDetectImage(
              _detector,
              image,
              options,
              result,
              error,
            ),
          );
        } else {
          _checked(
            (error) => mp.MpFaceDetectorDetectForVideo(
              _detector,
              image,
              options,
              timestamp,
              result,
              error,
            ),
          );
        }
        try {
          return FaceDetectorResult(
            imageWidth: mp.MpImageGetWidth(image),
            imageHeight: mp.MpImageGetHeight(image),
            timestampMilliseconds: timestamp,
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
