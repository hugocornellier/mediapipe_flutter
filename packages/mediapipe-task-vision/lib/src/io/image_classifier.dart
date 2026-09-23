import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../capabilities.dart';
import '../../third_party/mediapipe/vision_tasks_bindings.dart' as mp;
import '../../vision_task_backend.dart';
import '../sdk_vision_task.dart';
import '../capabilities/official_runtime_io.dart';
import 'native_ios_sdk.dart';
import 'native_vision_image.dart';
import 'native_vision_task.dart';
import 'vision_task_worker.dart';

/// Official Image Classifier with serialized inference on a worker isolate.
///
/// On Android, a registered official SDK adapter
/// (`mediapipe_flutter_vision_android`) runs the task; elsewhere Google's
/// native runtime runs it on a worker isolate.
final class ImageClassifier {
  ImageClassifier._(this._worker, this._sdk, this.delegate);
  final VisionTaskWorker<ImageClassifierResult>? _worker;
  final SdkVisionTask<ImageClassifierResult>? _sdk;

  /// Requested backend, fixed until disposal.
  final VisionDelegate delegate;

  /// Mode selected when creating this task.
  VisionRunningMode get runningMode =>
      _sdk?.runningMode ?? _worker!.runningMode;

  /// Load a model and initialize the official graph off the calling isolate.
  static Future<ImageClassifier> create(ImageClassifierOptions options) async {
    if (Platform.isAndroid && imageClassifierBackendFactory != null) {
      return ImageClassifier._(
        null,
        SdkVisionTask(
          await imageClassifierBackendFactory!(options),
          options.runningMode,
          options.delegate,
          name: 'ImageClassifier',
          // MediaPipe converts milliseconds to signed 64-bit microseconds.
          maxTimestamp: 0x7fffffffffffffff ~/ 1000,
        ),
        options.delegate,
      );
    }
    final capabilities = await queryImageClassifierCapabilities();
    if (!capabilities.supportedDelegates.contains(options.delegate)) {
      throw UnsupportedError(
        capabilities.unavailableReasons[options.delegate]!,
      );
    }
    return ImageClassifier._(
      await VisionTaskWorker.create(
        options,
        _createNative,
        'MediaPipe Image Classifier',
      ),
      null,
      options.delegate,
    );
  }

  /// Classify a still image or a normalized region using official preprocessing.
  Future<ImageClassifierResult> classifyImage(
    VisionImage image, {
    int rotationDegrees = 0,
    VisionRegionOfInterest? regionOfInterest,
  }) =>
      _sdk?.detectImage(
        image,
        rotationDegrees: rotationDegrees,
        regionOfInterest: regionOfInterest,
      ) ??
      _worker!.processImage(image, rotationDegrees, regionOfInterest);

  /// Classify a video frame with a strictly increasing millisecond timestamp.
  Future<ImageClassifierResult> classifyForVideo(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
    VisionRegionOfInterest? regionOfInterest,
  }) =>
      _sdk?.detectForVideo(
        image,
        timestampMilliseconds: timestampMilliseconds,
        rotationDegrees: rotationDegrees,
        regionOfInterest: regionOfInterest,
      ) ??
      _worker!.processVideo(
        image,
        rotationDegrees,
        timestampMilliseconds,
        regionOfInterest,
      );

  /// Drain queued requests and release native resources exactly once.
  Future<void> dispose() => _sdk?.dispose() ?? _worker!.dispose();
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
      native.ref.running_mode = nativeVisionRunningMode(options.runningMode);
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
