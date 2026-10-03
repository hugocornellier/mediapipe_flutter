import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:mediapipe_core/mediapipe_core.dart';

import '../../third_party/mediapipe/vision_tasks_bindings.dart' as mp;
import '../runner/native_interface.dart';
import '../types/options.dart';
import '../types/results.dart';
import '../types/vision_types.dart';
import '../capabilities/official_runtime_io.dart';
import 'native_desktop_runtime.dart';
import 'native_vision_image.dart';

/// Internal synchronous owner, used exclusively by the detector's worker isolate.
final class NativeObjectDetector
    implements NativeVisionTask<ObjectDetectorResult> {
  /// Creates the official IMAGE or VIDEO task with the requested delegate.
  NativeObjectDetector(ObjectDetectorOptions options)
    : _gpu = options.delegate == Delegate.gpu {
    if (!Platform.isMacOS &&
        !Platform.isLinux &&
        !hasOfficialIosVisionRuntime() &&
        _gpu) {
      throw UnsupportedError(
        'GPU object inference requires macOS, Linux or the official iOS SDK '
        'adapter.',
      );
    }
    loadOfficialDesktopRuntime();
    using((arena) {
      final native = arena<mp.MpObjectDetectorOptions>();
      final base = native.ref.base_options;
      base.file_descriptor = -1;
      base.delegate = options.delegate == Delegate.gpu
          ? mp.MpDelegate.MP_DELEGATE_GPU
          : mp.MpDelegate.MP_DELEGATE_CPU;
      base.host_system = Platform.isIOS
          ? mp.MpHostSystem.MP_HOST_SYSTEM_IOS
          : Platform.isLinux
          ? mp.MpHostSystem.MP_HOST_SYSTEM_LINUX
          : Platform.isWindows
          ? mp.MpHostSystem.MP_HOST_SYSTEM_WINDOWS
          : mp.MpHostSystem.MP_HOST_SYSTEM_MAC;
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
        // LIVE_STREAM runs on the VIDEO graph, with its flow limiter in
        // the task runner.
        ..running_mode = options.runningMode == RunningMode.image
            ? mp.MpRunningMode.MP_RUNNING_MODE_IMAGE
            : mp.MpRunningMode.MP_RUNNING_MODE_VIDEO
        ..max_results = options.maxResults
        ..score_threshold = options.scoreThreshold;
      if (options.displayNamesLocale case final locale?) {
        native.ref.display_names_locale = locale
            .toNativeUtf8(allocator: arena)
            .cast();
      }
      native.ref
        ..category_allowlist = _strings(arena, options.categoryAllowlist)
        ..category_allowlist_count = options.categoryAllowlist.length
        ..category_denylist = _strings(arena, options.categoryDenylist)
        ..category_denylist_count = options.categoryDenylist.length;
      final output = arena<mp.MpObjectDetectorPtr>();
      _checked((error) => mp.MpObjectDetectorCreate(native, output, error));
      _detector = output.value;
    });
  }

  mp.MpObjectDetectorPtr _detector = nullptr;
  final bool _gpu;

  /// Runs a single image and copies every result before releasing native memory.
  ObjectDetectorResult detect(
    VisionImage input,
    int rotation, {
    int? timestamp,
  }) {
    return using((arena) {
      final image = createVisionImage(
        arena,
        input,
        expandRgbForGpu: _gpu,
        checked: _checked,
      );
      try {
        final options = arena<mp.MpImageProcessingOptions>();
        options.ref.rotation_degrees = rotation;
        final result = arena<mp.MpObjectDetectorResult>();
        if (timestamp == null) {
          _checked(
            (error) => mp.MpObjectDetectorDetectImage(
              _detector,
              image,
              options,
              result,
              error,
            ),
          );
        } else {
          _checked(
            (error) => mp.MpObjectDetectorDetectForVideo(
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
          return ObjectDetectorResult(
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
          mp.MpObjectDetectorCloseResult(result);
        }
      } finally {
        mp.MpImageFree(image);
      }
    });
  }

  @override
  ObjectDetectorResult process(VisionTaskInput input) =>
      detect(input.$1, input.$2, timestamp: input.$3);

  /// Closes the task exactly once, including when native shutdown reports failure.
  @override
  void close() {
    if (_detector == nullptr) return;
    final pointer = _detector;
    _detector = nullptr;
    _checked((error) => mp.MpObjectDetectorClose(pointer, error));
  }
}

Pointer<Pointer<Char>> _strings(Arena arena, List<String> values) {
  if (values.isEmpty) return nullptr;
  final array = arena<Pointer<Char>>(values.length);
  for (var i = 0; i < values.length; i++) {
    array[i] = values[i].toNativeUtf8(allocator: arena).cast();
  }
  return array;
}

void _checked(mp.MpStatus Function(Pointer<Pointer<Char>>) call) => checkedCall(
  call,
  onError: (message, statusCode) =>
      TaskException(message, statusCode: statusCode),
);

Detection _copyDetection(mp.MpDetection value) => Detection(
  boundingBox: BoundingBox(
    left: value.bounding_box.left,
    top: value.bounding_box.top,
    right: value.bounding_box.right,
    bottom: value.bounding_box.bottom,
  ),
  categories: [
    for (var i = 0; i < value.categories_count; i++)
      MediaPipeCategory(
        index: value.categories[i].index,
        score: value.categories[i].score,
        categoryName: nativeString(value.categories[i].category_name),
        displayName: nativeString(value.categories[i].display_name),
      ),
  ],
);
