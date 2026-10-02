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

/// Google's Image Classifier on its worker isolate.
final class NativeImageClassifier
    implements NativeVisionTask<ImageClassifierResult> {
  /// Creates the task with the requested delegate and mode.
  NativeImageClassifier(ImageClassifierOptions options)
    : _gpu = options.delegate == Delegate.gpu {
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
    final (source, rotation, timestamp, region) = input;
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
