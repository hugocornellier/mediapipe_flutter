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

/// Official Image Classifier with serialized inference on a worker isolate.
///
/// On Android, a registered official SDK adapter
/// (`mediapipe_vision`) runs the task; elsewhere Google's
/// native runtime runs it on a worker isolate.
///
/// ```dart
/// final task = await ImageClassifier.create(
///   ImageClassifierOptions(model: VisionModels.imageClassifier),
/// );
/// final image = VisionImage.fromFile('photo.jpg');
/// final result = await task.classifyImage(image);
/// await task.dispose();
/// ```
/// Inference futures cannot cancel native work; `Future.timeout` only limits
/// caller waiting. `dispose()` drains accepted work and is idempotent.
final class ImageClassifier {
  ImageClassifier._(this._task, this.delegate);
  final VisionTaskRunner<ImageClassifierResult> _task;

  /// Requested backend, fixed until disposal.
  final VisionDelegate delegate;

  /// Mode selected when creating this task.
  RunningMode get runningMode => _task.runningMode;

  /// Load a model and initialize the official graph off the calling isolate.
  static Future<ImageClassifier> create(ImageClassifierOptions options) async =>
      ImageClassifier._(
        await VisionTaskRunner.open(
          options,
          name: 'ImageClassifier',
          debugName: 'MediaPipe Image Classifier',
          android: imageClassifierBackendFactory,
          capabilities: queryImageClassifierCapabilities,
          native: _createNative,
        ),
        options.delegate,
      );

  /// Classify a still image or a normalized region using official preprocessing.
  Future<ImageClassifierResult> classifyImage(
    VisionImage image, {
    int rotationDegrees = 0,
    VisionRegionOfInterest? regionOfInterest,
  }) => _task.image(image, rotationDegrees, regionOfInterest: regionOfInterest);

  /// Classify a video frame with a strictly increasing millisecond timestamp.
  Future<ImageClassifierResult> classifyForVideo(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
    VisionRegionOfInterest? regionOfInterest,
  }) => _task.video(
    image,
    rotationDegrees,
    timestampMilliseconds,
    regionOfInterest: regionOfInterest,
  );

  /// Drain queued requests and release native resources exactly once.
  Future<void> dispose() => _task.dispose();
}

NativeVisionTask<ImageClassifierResult> _createNative(
  ImageClassifierOptions options,
) => _NativeImageClassifier(options);

final class _NativeImageClassifier
    implements NativeVisionTask<ImageClassifierResult> {
  _NativeImageClassifier(ImageClassifierOptions options)
    : _gpu = options.delegate == VisionDelegate.gpu {
    using((arena) {
      final native = arena<mp.MpImageClassifierOptions>();
      setVisionBaseOptions(
        arena,
        native.ref.base_options,
        options,
        officialGpu: true,
      );
      native.ref.running_mode = nativeRunningMode(options.runningMode);
      final classifier = native.ref.classifier_options;
      classifier
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
        classifier.display_names_locale = locale
            .toNativeUtf8(allocator: arena)
            .cast();
      }
      final output = arena<mp.MpImageClassifierPtr>();
      checkVisionCreate(
        (error) => mp.MpImageClassifierCreate(native, output, error),
        gpu: _gpu,
      );
      _task = output.value;
    });
  }
  final bool _gpu;
  mp.MpImageClassifierPtr _task = nullptr;
  late final IosBgraStorage? _iosBgra =
      hasOfficialIosVisionRuntime() && iosImageStorageMode != 0
      ? IosBgraStorage(iosImageStorageMode)
      : null;

  @override
  ImageClassifierResult process(VisionTaskInput input) => using((arena) {
    final (source, rotation, timestamp, region, _) = input;
    final image = createVisionImage(
      arena,
      source,
      expandRgbForGpu: _gpu,
      checked: checkVisionCall,
      iosBgra: _iosBgra,
    );
    try {
      final processing = visionProcessingOptions(arena, rotation, region);
      final result = arena<mp.MpImageClassifierResult>();
      if (timestamp == null) {
        checkVisionCall(
          (error) => mp.MpImageClassifierClassifyImage(
            _task,
            image,
            processing,
            result,
            error,
          ),
        );
      } else {
        checkVisionCall(
          (error) => mp.MpImageClassifierClassifyForVideo(
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
        return ImageClassifierResult(
          classifications: copyVisionClassifications(result.ref),
          imageWidth: mp.MpImageGetWidth(image),
          imageHeight: mp.MpImageGetHeight(image),
          timestampMilliseconds: timestamp,
        );
      } finally {
        mp.MpImageClassifierCloseResult(result);
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
      checkVisionCall((error) => mp.MpImageClassifierClose(task, error));
    } finally {
      _iosBgra?.close();
    }
  }
}
