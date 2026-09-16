import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../capabilities.dart';
import '../../third_party/mediapipe/vision_tasks_bindings.dart' as mp;
import '../interface/segmenter_task_types.dart';
import 'native_vision_image.dart';
import 'native_vision_task.dart';
import 'vision_task_worker.dart';

/// Official stateless MagicTouch segmenter, selecting the object under a point.
///
/// This is not the stateful `InteractiveSegmenter`: that task keeps stroke
/// history on Google's 1.0.1 runtime and has its own API and blockers.
final class InteractiveSegmenterLegacy {
  InteractiveSegmenterLegacy._(this._worker, this.delegate);
  final VisionTaskWorker<SegmentationResult> _worker;

  /// Requested backend, fixed until disposal.
  final VisionDelegate delegate;

  /// Load the MagicTouch model and open its graph off the calling isolate.
  static Future<InteractiveSegmenterLegacy> create(
    InteractiveSegmenterLegacyOptions options,
  ) async {
    final capabilities = await querySegmenterTaskCapabilities();
    if (!capabilities.supportedDelegates.contains(options.delegate)) {
      throw UnsupportedError(
        capabilities.unavailableReasons[options.delegate]!,
      );
    }
    return InteractiveSegmenterLegacy._(
      await VisionTaskWorker.create(
        options,
        _createNative,
        'MediaPipe Interactive Segmenter Legacy',
      ),
      options.delegate,
    );
  }

  /// Segment the object under [keypoint], in normalized image coordinates.
  ///
  /// Segmentation rejects a cropping region of interest, as the official
  /// task does, so only rotation preprocessing is offered.
  ///
  /// Google's official 1.0.0 bindings expose only this keypoint form, so the
  /// scribble format the C API also accepts has no independent reference and
  /// is deliberately not offered here.
  Future<SegmentationResult> segmentImage(
    VisionImage image, {
    required SegmentationPoint keypoint,
    int rotationDegrees = 0,
  }) => _worker.processImage(image, rotationDegrees, null, keypoint: keypoint);

  /// Drain queued requests and release native resources exactly once.
  Future<void> dispose() => _worker.dispose();
}

NativeVisionTask<SegmentationResult> _createNative(
  InteractiveSegmenterLegacyOptions options,
) => _NativeInteractiveSegmenterLegacy(options);

final class _NativeInteractiveSegmenterLegacy
    implements NativeVisionTask<SegmentationResult> {
  _NativeInteractiveSegmenterLegacy(InteractiveSegmenterLegacyOptions options)
    : _gpu = options.delegate == VisionDelegate.gpu {
    using((arena) {
      final native = arena<mp.MpInteractiveSegmenterLegacyOptions>();
      setVisionBaseOptions(arena, native.ref.base_options, options);
      native.ref
        ..output_confidence_masks = options.outputConfidenceMasks
        ..output_category_mask = options.outputCategoryMask;
      final output = arena<mp.MpInteractiveSegmenterLegacyPtr>();
      checkVisionCall(
        (error) => mp.MpInteractiveSegmenterLegacyCreate(native, output, error),
      );
      _task = output.value;
    });
  }
  final bool _gpu;
  mp.MpInteractiveSegmenterLegacyPtr _task = nullptr;

  @override
  SegmentationResult process(VisionTaskInput input) => using((arena) {
    final (source, rotation, timestamp, _, keypoint) = input;
    if (keypoint == null) {
      throw const VisionTaskException(
        'Interactive segmentation requires a region-of-interest point.',
      );
    }
    final image = createVisionImage(
      arena,
      source,
      expandRgbForGpu: _gpu,
      checked: checkVisionCall,
    );
    try {
      final point = arena<mp.MpNormalizedKeypoint>();
      point.ref
        ..x = keypoint.x
        ..y = keypoint.y;
      final roi = arena<mp.MpRegionOfInterest>();
      roi.ref
        ..format =
            mp.MpRegionOfInterestFormat.MP_REGION_OF_INTEREST_FORMAT_KEYPOINT
        ..keypoint = point;
      final processing = visionProcessingOptions(arena, rotation, null);
      final result = arena<mp.MpImageSegmenterResult>();
      checkVisionCall(
        (error) => mp.MpInteractiveSegmenterLegacySegmentImage(
          _task,
          image,
          roi,
          processing,
          result,
          error,
        ),
      );
      try {
        return copyVisionSegmentation(arena, result.ref, image, timestamp);
      } finally {
        mp.MpInteractiveSegmenterLegacyCloseResult(result);
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
    checkVisionCall(
      (error) => mp.MpInteractiveSegmenterLegacyClose(task, error),
    );
  }
}
