import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../capabilities.dart';
import '../../third_party/mediapipe/vision_tasks_bindings.dart' as mp;
import '../vision_task_backend.dart';
import '../capabilities/official_runtime_io.dart';
import 'native_ios_sdk.dart';
import 'native_vision_image.dart';
import 'native_vision_task.dart';
import 'vision_task_runner.dart';
import 'vision_task_worker.dart';

/// Official Image Segmenter with owned masks and serialized inference.
///
/// On Android, a registered official SDK adapter
/// (`mediapipe_vision`) runs the task; elsewhere Google's
/// native runtime runs it on a worker isolate.
///
/// ```dart
/// final task = await ImageSegmenter.create(
///   ImageSegmenterOptions(model: VisionModels.imageSegmenter),
/// );
/// final image = VisionImage.fromFile('photo.jpg');
/// final result = await task.segmentImage(image);
/// await task.dispose();
/// ```
/// Inference futures cannot cancel native work; `Future.timeout` only limits
/// caller waiting. `dispose()` drains accepted work and is idempotent.
final class ImageSegmenter {
  ImageSegmenter._(this._task, this.delegate);
  final VisionTaskRunner<SegmentationResult> _task;

  /// Requested backend, fixed until disposal.
  final VisionDelegate delegate;

  /// Mode selected when creating this task.
  RunningMode get runningMode => _task.runningMode;

  /// Load a segmentation model and open its graph off the calling isolate.
  static Future<ImageSegmenter> create(ImageSegmenterOptions options) async =>
      ImageSegmenter._(
        await VisionTaskRunner.open(
          options,
          name: 'ImageSegmenter',
          debugName: 'MediaPipe Image Segmenter',
          android: imageSegmenterBackendFactory,
          capabilities: queryImageSegmenterCapabilities,
          native: _createNative,
        ),
        options.delegate,
      );

  /// Segment one still image with official rotation preprocessing.
  ///
  /// Segmentation rejects a cropping region of interest, as the official
  /// task does, so only rotation preprocessing is offered.
  Future<SegmentationResult> segmentImage(
    VisionImage image, {
    int rotationDegrees = 0,
  }) => _task.image(image, rotationDegrees);

  /// Segment a video frame with a strictly increasing millisecond timestamp.
  Future<SegmentationResult> segmentForVideo(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
  }) => _task.video(image, rotationDegrees, timestampMilliseconds);

  /// Drain queued requests and release native resources exactly once.
  Future<void> dispose() => _task.dispose();
}

NativeVisionTask<SegmentationResult> _createNative(
  ImageSegmenterOptions options,
) => _NativeImageSegmenter(options);

final class _NativeImageSegmenter
    implements NativeVisionTask<SegmentationResult> {
  _NativeImageSegmenter(ImageSegmenterOptions options)
    : _gpu = options.delegate == VisionDelegate.gpu {
    using((arena) {
      final native = arena<mp.MpImageSegmenterOptions>();
      setVisionBaseOptions(
        arena,
        native.ref.base_options,
        options,
        officialGpu: true,
      );
      native.ref
        ..running_mode = nativeRunningMode(options.runningMode)
        ..output_confidence_masks = options.outputConfidenceMasks
        ..output_category_mask = options.outputCategoryMask;
      // MpImageSegmenterCreate dereferences this pointer unconditionally and
      // segfaults on null, unlike the classifier options, whose C code checks.
      // Google's own bindings always pass a string; see upstream-issues.md
      // UP-009.
      native.ref.display_names_locale = (options.displayNamesLocale ?? '')
          .toNativeUtf8(allocator: arena)
          .cast();
      final output = arena<mp.MpImageSegmenterPtr>();
      checkVisionCreate(
        (error) => mp.MpImageSegmenterCreate(native, output, error),
        gpu: _gpu,
      );
      _task = output.value;
      _labels = _readLabels(arena);
    });
  }
  final bool _gpu;
  mp.MpImageSegmenterPtr _task = nullptr;
  List<String> _labels = const [];
  late final IosBgraStorage? _iosBgra =
      hasOfficialIosVisionRuntime() && iosImageStorageMode != 0
      ? IosBgraStorage(iosImageStorageMode)
      : null;

  /// The model's category order, read once while the task is initialized.
  List<String> _readLabels(Arena arena) {
    final list = arena<mp.MpStringList>();
    checkVisionCall(
      (error) => mp.MpImageSegmenterGetLabels(_task, list, error),
    );
    try {
      return [
        for (var i = 0; i < list.ref.num_strings; i++)
          nativeString(list.ref.strings[i]) ?? '',
      ];
    } finally {
      mp.MpStringListFree(list);
    }
  }

  @override
  SegmentationResult process(VisionTaskInput input) => using((arena) {
    final (source, rotation, timestamp, _, _) = input;
    final image = createVisionImage(
      arena,
      source,
      expandRgbForGpu: _gpu,
      checked: checkVisionCall,
      iosBgra: _iosBgra,
    );
    try {
      final processing = visionProcessingOptions(arena, rotation, null);
      final result = arena<mp.MpImageSegmenterResult>();
      if (timestamp == null) {
        checkVisionCall(
          (error) => mp.MpImageSegmenterSegmentImage(
            _task,
            image,
            processing,
            result,
            error,
          ),
        );
      } else {
        checkVisionCall(
          (error) => mp.MpImageSegmenterSegmentForVideo(
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
        return copyVisionSegmentation(
          arena,
          result.ref,
          image,
          timestamp,
          labels: _labels,
        );
      } finally {
        mp.MpImageSegmenterCloseResult(result);
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
      checkVisionCall((error) => mp.MpImageSegmenterClose(task, error));
    } finally {
      _iosBgra?.close();
    }
  }
}
