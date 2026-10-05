import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:mediapipe_core/mediapipe_core.dart';

import '../../third_party/mediapipe/vision_tasks_bindings.dart' as mp;
import '../capabilities/official_runtime_io.dart';
import '../runner/native_interface.dart';
import '../types/options.dart';
import '../types/results.dart';
import 'native_ios_sdk.dart';
import 'native_vision_image.dart';
import 'native_vision_task.dart';

/// Google's Object Detector on its worker isolate.
final class NativeObjectDetector
    implements NativeVisionTask<ObjectDetectorResult> {
  /// Creates the task with the requested delegate and mode.
  NativeObjectDetector(ObjectDetectorOptions options)
    : _gpu = options.delegate == Delegate.gpu {
    using((arena) {
      final native = arena<mp.MpObjectDetectorOptions>();
      setVisionBaseOptions(
        arena,
        native.ref.base_options,
        options,
        officialGpu: true,
      );
      native.ref
        ..running_mode = nativeRunningMode(options.runningMode)
        ..max_results = options.maxResults
        ..score_threshold = options.scoreThreshold
        ..category_allowlist = visionOptionStrings(
          arena,
          options.categoryAllowlist,
        )
        ..category_allowlist_count = options.categoryAllowlist.length
        ..category_denylist = visionOptionStrings(
          arena,
          options.categoryDenylist,
        )
        ..category_denylist_count = options.categoryDenylist.length;
      if (options.displayNamesLocale case final locale?) {
        native.ref.display_names_locale = locale
            .toNativeUtf8(allocator: arena)
            .cast();
      }
      final output = arena<mp.MpObjectDetectorPtr>();
      checkVisionCreate(
        (error) => mp.MpObjectDetectorCreate(native, output, error),
        gpu: _gpu,
      );
      _task = output.value;
    });
  }
  final bool _gpu;
  mp.MpObjectDetectorPtr _task = nullptr;
  late final IosBgraStorage? _iosBgra = hasOfficialIosVisionRuntime()
      ? iosBgraStorage()
      : null;

  @override
  ObjectDetectorResult process(VisionTaskInput input) => using((arena) {
    final (source, rotation, timestamp, _) = input;
    final image = createVisionImage(
      arena,
      source,
      expandRgbForGpu: _gpu,
      checked: checkVisionCall,
      iosBgra: _iosBgra,
    );
    try {
      final processing = visionProcessingOptions(arena, rotation, null);
      final result = arena<mp.MpObjectDetectorResult>();
      if (timestamp == null) {
        checkVisionCall(
          (error) => mp.MpObjectDetectorDetectImage(
            _task,
            image,
            processing,
            result,
            error,
          ),
        );
      } else {
        checkVisionCall(
          (error) => mp.MpObjectDetectorDetectForVideo(
            _task,
            image,
            processing,
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
        mp.MpObjectDetectorCloseResult(result);
      }
    } finally {
      mp.MpImageFree(image);
    }
  });

  @override
  void close() {
    if (_task == nullptr) return;
    final task = _task;
    _task = nullptr;
    try {
      checkVisionCall((error) => mp.MpObjectDetectorClose(task, error));
    } finally {
      _iosBgra?.close();
    }
  }
}

Detection _copyDetection(mp.MpDetection value) => Detection(
  boundingBox: BoundingBox(
    left: value.bounding_box.left,
    top: value.bounding_box.top,
    right: value.bounding_box.right,
    bottom: value.bounding_box.bottom,
  ),
  categories: [
    for (var i = 0; i < value.categories_count; i++)
      copyVisionCategory(value.categories[i]),
  ],
);
